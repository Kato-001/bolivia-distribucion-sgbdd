FROM python:3.12-slim
RUN pip install --no-cache-dir "psycopg[binary]==3.2.3"
WORKDIR /app
COPY coordinador_2pc.py .
ENTRYPOINT ["python", "-u", "coordinador_2pc.py"]
