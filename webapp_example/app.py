import os
import requests
from flask import Flask, render_template, request

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/translate', methods=['POST'])
def translate():
    auth_key = os.environ.get('DEEPL_KEY')

    text = request.form['text-input']
    target_language = request.form['language-select']
    
    url = "https://api-free.deepl.com/v2/translate"

    headers = {
        "Authorization": f"DeepL-Auth-Key {auth_key}"
    }

    text = text.encode('utf-8') 
    
    data = {
        "text": text,
        "target_lang": target_language
    }

    response = requests.post(url, headers=headers, data=data)
    
    translated_text = response.json()['translations'][0]['text']

    return render_template('index.html', output=translated_text)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
