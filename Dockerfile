# Imagen oficial de Playwright para Python — incluye Chromium y todas sus dependencias
FROM mcr.microsoft.com/playwright/python:v1.47.0-jammy

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Instalar solo Chromium (más liviano que instalar todos los browsers)
RUN playwright install chromium

COPY . .

# Volumen para persistir la base de datos SQLite
VOLUME ["/data"]

EXPOSE 8000

CMD ["python", "main.py"]
