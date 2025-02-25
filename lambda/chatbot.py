import os
import boto3
import json
import requests
from uuid import uuid4
from datetime import datetime

# Get environment variables
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE")
WEATHER_API_KEY = os.getenv("WEATHER_API_KEY")

# Initialize DynamoDB client
dynamodb = boto3.client("dynamodb")

def get_weather(city):
    """Fetch weather data from a weather API."""
    url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={WEATHER_API_KEY}"
    response = requests.get(url)
    if response.status_code == 200:
        return response.json()
    return {"error": "Unable to fetch weather data"}

def get_joke():
    """Fetch a random joke from an external API."""
    url = "https://official-joke-api.appspot.com/jokes/random"
    response = requests.get(url)
    if response.status_code == 200:
        joke_data = response.json()
        return f"{joke_data['setup']} {joke_data['punchline']}"
    return "Unable to fetch a joke at the moment."

def lambda_handler(event, context):
    try:
        body = json.loads(event["body"])
        query = body.get("query", "")

        if "weather" in query.lower():
            city = query.split("in")[-1].strip()
            response_data = get_weather(city)
            response_text = f"Weather in {city}: {response_data}" if "error" not in response_data else response_data["error"]
        elif "joke" in query.lower():
            response_text = get_joke()
        else:
            response_text = f"Mock response for: {query}"

        # Store the query and response in DynamoDB
        dynamodb.put_item(
            TableName=DYNAMODB_TABLE,
            Item={
                "request_id": {"S": str(uuid4())},
                "query": {"S": query},
                "response": {"S": response_text},
                "timestamp": {"S": datetime.utcnow().isoformat()}
            }
        )

        return {
            "statusCode": 200,
            "body": json.dumps({"response": response_text})
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
