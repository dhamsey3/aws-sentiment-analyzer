import boto3
import csv
import io
import json
import os
from datetime import datetime

from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

s3 = boto3.client('s3')
analyzer = SentimentIntensityAnalyzer()

POSITIVE_THRESHOLD = 0.05
NEGATIVE_THRESHOLD = -0.05


def get_latest_file(bucket, prefix):
    try:
        files = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
        if 'Contents' not in files or not files['Contents']:
            raise ValueError(
                f"No files found in bucket {bucket} with prefix {prefix}"
            )
        return max(files['Contents'], key=lambda x: x['LastModified'])
    except Exception as e:
        print(f"Error in get_latest_file: {str(e)}")
        raise


def get_file_content(bucket, key):
    try:
        print(f"Reading file: {key}")
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        return json.loads(content)
    except Exception as e:
        print(f"Error reading file: {str(e)}")
        raise


def classify(compound):
    if compound >= POSITIVE_THRESHOLD:
        return "positive"
    if compound <= NEGATIVE_THRESHOLD:
        return "negative"
    return "neutral"


def score_entries(data):
    scored = []
    for entry in data:
        text = entry.get('text', '')
        text = text.replace('\n', ' ').replace('\r', ' ').strip()
        if not text:
            continue

        scores = analyzer.polarity_scores(text)
        scored.append({
            'id': entry.get('id', ''),
            'text': text,
            'compound': scores['compound'],
            'positive': scores['pos'],
            'neutral': scores['neu'],
            'negative': scores['neg'],
            'label': classify(scores['compound']),
            'created_utc': entry.get('created_utc', ''),
        })
    return scored


def save_results(bucket, scored):
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    key = f"processed_data/sentiment_{timestamp}.csv"

    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(['id', 'label', 'compound', 'positive', 'neutral', 'negative', 'created_utc', 'text'])
    for entry in scored:
        writer.writerow([
            entry['id'], entry['label'], entry['compound'], entry['positive'],
            entry['neutral'], entry['negative'], entry['created_utc'], entry['text'],
        ])

    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=output.getvalue(),
        ContentType='text/csv',
    )
    print(f"Successfully saved sentiment results to {key}")
    return key


def lambda_handler(event, context):
    try:
        bucket = os.environ['S3_BUCKET']
        print(f"Starting processing for bucket: {bucket}")

        reddit_prefix = 'raw_data/reddit/'
        latest_reddit_file = get_latest_file(bucket, reddit_prefix)
        reddit_data = get_file_content(bucket, latest_reddit_file['Key'])

        if not isinstance(reddit_data, list):
            raise ValueError("Input data must be a list of objects")

        scored = score_entries(reddit_data)
        output_key = save_results(bucket, scored)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sentiment analysis complete',
                'output_file': output_key,
                'entries_processed': len(scored),
            })
        }

    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Error processing sentiment data',
            })
        }

