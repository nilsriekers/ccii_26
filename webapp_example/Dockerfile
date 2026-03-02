# Verwende ein Python 3.11-Image als Basis
FROM python:3.11-slim

# Setze das Arbeitsverzeichnis im Container
WORKDIR /app

# Kopiere die pyproject.toml- und poetry.lock-Dateien in das Arbeitsverzeichnis
COPY pyproject.toml poetry.lock /app/

# Installiere Poetry
RUN pip install poetry

# Installiere die Abhängigkeiten
RUN poetry install --no-root

# Kopiere die restlichen Dateien in das Arbeitsverzeichnis
COPY . /app/

# Setze die Umgebungsvariable für den Flask-Server
ENV FLASK_APP=app.py

# Setze den Port, auf dem der Flask-Server laufen soll
EXPOSE 5000

# Starte den Flask-Server beim Starten des Containers
CMD ["poetry", "run", "flask", "run", "--host=0.0.0.0", "--port=5000"]

