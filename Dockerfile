# Use an official lightweight Python image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy app code
COPY . /app

# Install dependencies
RUN pip install flask

# Expose port 5000
EXPOSE 5000

# Run the app
CMD ["python", "app.py"]
