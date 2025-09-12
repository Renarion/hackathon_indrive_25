import os
from flask import Flask, request, jsonify
import json
import pandas as pd
import numpy as np
import typing as t
import google.generativeai as genai
import time
import cv2
import speech_recognition as sr
from vertexai.generative_models import Image
import PIL.Image
import requests
from datetime import datetime
from typing import Dict
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

print('Hello, world')

app = Flask(__name__)

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "7962185676:AAEq4Ok9EfVbEx_poPKeO-YDtVPl_WmdUOc")
CHANNEL_ID = os.environ.get("TELEGRAM_CHANNEL_ID", "@incident_reports")
API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyCegpz8E8NNpPm9M3_ZPcDghPDATnDwouY")
genai.configure(api_key=API_KEY)
model = genai.GenerativeModel('models/gemini-2.5-flash', generation_config={"temperature": 0.0, "response_mime_type": "application/json"})

TEMP_DIR = "temp_uploads"
if not os.path.exists(TEMP_DIR):
    os.makedirs(TEMP_DIR)


# WAV TO TEXT
def transcribe_audio_from_file(audio_path: str) -> str:
    recognizer = sr.Recognizer()

    try:
        with sr.AudioFile(audio_path) as source:
            audio_data = recognizer.record(source)
    except FileNotFoundError:
        return f"Ошибка: Файл не найден по пути {audio_path}"

    try:
        text = recognizer.recognize_google(audio_data, language="ru-RU")
        return text
    except sr.UnknownValueError:
        return "Не удалось распознать речь"
    except sr.RequestError:
        return "Ошибка сервиса распознавания; проверьте интернет-соединение"
    
# PNG TO PIL
def load_images_for_gemini(image_paths: t.List[str]) -> t.List[PIL.Image.Image]:
    loaded_images = []
    for path in image_paths:
        try:
            cv2_image = cv2.imread(path)
            
            if cv2_image is None:
                raise ValueError("Файл не является изображением или повреждён.")
            
            rgb_image = cv2.cvtColor(cv2_image, cv2.COLOR_BGR2RGB)
            
            pil_image = PIL.Image.fromarray(rgb_image)
            
            loaded_images.append(pil_image)
            
        except FileNotFoundError:
            print(f"Ошибка: Файл не найден по пути '{path}'. Пропускаем.")
        except Exception as e:
            print(f"Ошибка при обработке файла '{path}': {e}. Пропускаем.")
            
    return loaded_images


# GENERATE REPORT
def generate_incident_report_with_multiple_images(
    audio_transcript: str, 
    incident_images: t.List[PIL.Image.Image]
) -> t.Optional[str]:
    try:
        prompt = f"""
        You are an AI assistant for a taxi app, specializing in incident reports.
        You analyze two sources of information: an audio transcript and a photo.

        Your task is to create a concise report on a potential incident. The analysis for each section should be brief, not more than 750 characters in total, consisting of **short 1-2 sentence paragraphs separated by a dash or a new line**.

        1.  **Analyze** the photo and the audio transcript.
        2.  **Correlate** the audio with the visual evidence.
        3.  **Formulate a plausible hypothesis** on what happened.
        4.  **Assign a final score from 0 to 10** for an incident manager to prioritize, where:
            * **0** indicates no incident and no need for investigation.
            * **10** indicates a confirmed, serious incident that requires immediate action.

        Format the response as a JSON object with the following structure:

        "report":
            "audio_analysis": "Your brief analysis here.",
            "image_analysis": "Your brief analysis here.",
            "correlation": "Your brief correlation here.",
            "hypothesis": "Your plausible hypothesis here.",
            "investigation_score": "Your score from 0 to 10 here.",
            "score_reasoning": "A brief explanation for the score."
        ---
        {audio_transcript}
        """
        content_parts = [prompt] 
        content_parts.extend(incident_images)
        response = model.generate_content(content_parts)
        
        return response.text.strip()

    except Exception as e:
        print(f"Ошибка при генерации отчёта: {e}")
        return None

# SENDING THE MESSAGE TO TELEGRAM
def send_telegram_message(text: str) -> bool:
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = {
        'chat_id': CHANNEL_ID,
        'text': text,
        'parse_mode': 'Markdown'
    }
    try:
        response = requests.post(url, data=data)
        response_data = response.json()
        if response_data.get("ok"):
            print("Текстовый отчёт успешно отправлен.")
            return True
        else:
            print(f"Ошибка отправки текста: {response_data.get('description')}")
            return False
    except Exception as e:
        print(f"Произошла ошибка при отправке текста: {e}")
        return False

# SENDING THE PHOTOS TO TELEGRAM
def send_telegram_photo_album(photo_paths: t.List[str], caption: str = "") -> bool:
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMediaGroup"
    files_to_upload = {}
    media_group = []
    
    try:
        for i, photo_path in enumerate(photo_paths):
            file_attach_name = f"photo{i}"
            files_to_upload[file_attach_name] = open(photo_path, 'rb')
            media_photo = {'type': 'photo', 'media': f'attach://{file_attach_name}'}
            if i == 0 and caption: # Подпись только к первому фото
                media_photo['caption'] = caption
            media_group.append(media_photo)
            
        data = {'chat_id': CHANNEL_ID, 'media': json.dumps(media_group)}
        print("Отправка фото-альбома...")
        response = requests.post(url, data=data, files=files_to_upload)
        response_data = response.json()
        if response_data.get("ok"):
            print("Фото-альбом успешно отправлен.")
            return True
        else:
            print(f"Ошибка отправки фото-альбома: {response_data.get('description')}")
            return False
    except Exception as e:
        print(f"Ошибка при формировании фото-альбома: {e}")
        return False
    finally:
        for file in files_to_upload.values():
            file.close()

# SENDING THE AUDIO TO TELEGRAM
def send_telegram_audio(audio_path: str) -> bool:
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendAudio"
    try:
        with open(audio_path, 'rb') as audio_file:
            files = {'audio': audio_file}
            data = {'chat_id': CHANNEL_ID}
            print("Отправка аудиофайла...")
            response = requests.post(url, data=data, files=files)
            response_data = response.json()
            if response_data.get("ok"):
                print("Аудиофайл успешно отправлен.")
                return True
            else:
                print(f"Ошибка отправки аудио: {response_data.get('description')}")
                return False
    except Exception as e:
        print(f"Произошла ошибка при отправке аудио: {e}")
        return False

# SENDING THE SPEECH TO TEXT FILE TO TELEGRAM
def send_text_file_to_telegram(text: str) -> bool:

    temp_file_path = "Transcribed audio.txt"
    
    try:
        with open(temp_file_path, 'w', encoding='utf-8') as f:
            f.write(text)
        
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendDocument"
        
        with open(temp_file_path, 'rb') as doc_file:
            files = {'document': doc_file}
            data = {'chat_id': CHANNEL_ID}
            
            response = requests.post(url, data=data, files=files)
            response_data = response.json()

            if response_data.get("ok"):
                print("Файл успешно отправлен.")
                return True
            else:
                print(f"Ошибка отправки файла: {response_data.get('description')}")
                return False

    except FileNotFoundError:
        print(f"Ошибка: Не удалось создать файл по пути {temp_file_path}")
        return False
    except requests.exceptions.RequestException as e:
        print(f"Ошибка сети при отправке файла: {e}")
        return False
    except Exception as e:
        print(f"Произошла непредвиденная ошибка: {e}")
        return False
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

# CREATING THE GOOGLE MAPS LINK BY LATITUDE AND LONGITUDE
def create_google_maps_link(latitude: float, longitude: float) -> str:
    link = f"https://www.google.com/maps/search/?api=1&query={latitude},{longitude}"
    return link

# FORMATTING TO PROPER DATE
def convert_timestamp_to_date(timestamp: float) -> str:
    """
    Converts a timestamp into a string of the format "10 октября 21:00".

    Args:
        timestamp (float): The timestamp in seconds.

    Returns:
        str: The formatted date and time string.
    """
    dt_object: datetime = datetime.fromtimestamp(timestamp)
    
    months: Dict[int, str] = {
        1: "January", 2: "February", 3: "March", 4: "April", 
        5: "May", 6: "June", 7: "July", 8: "August", 
        9: "September", 10: "October", 11: "November", 12: "December"
    }
    
    day: int = dt_object.day
    month: str = months[dt_object.month]
    hour: int = dt_object.hour
    minute: int = dt_object.minute
    second: int = dt_object.second
    
    formatted_hour: str = f"{hour:02d}"
    formatted_minute: str = f"{minute:02d}"
    formatted_second: str = f"{second:02d}"
    
    return f"{day} {month} {formatted_hour}:{formatted_minute}:{formatted_second}"

# RESULT FUNCTION TO SEND THE REPORT TO TELEGRAM
def generate_and_send_report(report_data: dict, image_paths: t.List[str], audio_path: str, STT: str, LATITUDE: float, LONGITUDE: float, START_INC_ST: float):

    logging.info("Generating")
    try:
        report_content = report_data['report']
        audio_analysis = report_content['audio_analysis']
        image_analysis = report_content['image_analysis']
        correlation = report_content['correlation']
        hypothesis = report_content['hypothesis']
        score = report_content['investigation_score']
        score_reasoning = report_content['score_reasoning']

        logging.info("Before location")
        location = create_google_maps_link(LATITUDE, LONGITUDE)
        date = convert_timestamp_to_date(START_INC_ST)
        logging.info("After location")

        formatted_text_common = f"""
*🚨 Report of a Potential Incident as of {date}*

*📍 Location:*
[Link to Google Maps]({location})

*🆘 Danger score:* `{score}/10`

*Justification:* `{score_reasoning}`

*🗂️ Analysis:*

*Audio:* `{audio_analysis}`

*Photos:* `{image_analysis}`

*🔗 Correlation:*

`{correlation}`

*🔎 Conclusion:*

`{hypothesis}`
        """
        
        print("Report ready to send")
        
        send_telegram_photo_album(
            photo_paths=image_paths
        )
        send_telegram_audio(audio_path)

        send_text_file_to_telegram(STT)

        time.sleep(1)

        send_telegram_message(formatted_text_common)
        
    except KeyError as e:
        print(f"Error: No token was found '{e}' in the structure.")
    except Exception as e:
        print(f"Unknown error: {e}")

@app.route('/checking', methods=['GET'])
def status_check():
    return "Server is up and running!!!"

@app.route('/uploading_to_gemini', methods=['POST'])
def handle_incident_upload():

    try:
        logging.info("The request was recieved")

        audio_file = request.files.get('audio')
        photos = request.files.getlist('photos') 
        
        latitude = request.form.get('latitude')
        longitude = request.form.get('longitude')
        timestamp = request.form.get('timestamp')

        if not audio_file or not photos or not latitude or not longitude or not timestamp:
            logging.warning("Not enough files")
            return jsonify({"Error": "Missing required fields: audio, photos, latitude, longitude, or timestamp"}), 400

        audio_path = os.path.join(TEMP_DIR, audio_file.filename)
        audio_file.save(audio_path)
        
        image_paths = []
        for photo in photos:
            photo_path = os.path.join(TEMP_DIR, photo.filename)
            photo.save(photo_path)
            image_paths.append(photo_path)
            
        logging.info(f"Files saved. Audio: {audio_path}, Photos: {image_paths}")

        
        audio_transcript = transcribe_audio_from_file(audio_path)
        
        images_for_gemini = load_images_for_gemini(image_paths)
        
        report_text = generate_incident_report_with_multiple_images(audio_transcript, images_for_gemini)
        
        if report_text:
            report_data = json.loads(report_text)
            generate_and_send_report(report_data, image_paths, audio_path, audio_transcript, float(latitude), float(longitude), float(timestamp))
            logging.info("Report sent to telegram")
        else:
            logging.error("Not managed to generate the report")
            return jsonify({"error": "Failed to generate report from Gemini"}), 500

        # 5. Очистка временных файлов
        os.remove(audio_path)
        for path in image_paths:
            os.remove(path)
        logging.info("File was deleted")
        
        return jsonify({"status": "success", "message": "Report generated and sent to Telegram."})

    except Exception as e:
        logging.error(f"Error while processing: {e}", exc_info=True)
        return jsonify({"Error": "An internal server error occurred"}), 500

if __name__ == '__main__':
    HOST_IP = '0.0.0.0'
    PORT = 5000
    print(f"Server Flask is working on http://{HOST_IP}:{PORT}")
    app.run(host=HOST_IP, port=PORT, debug=True)