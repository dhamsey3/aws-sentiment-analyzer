import praw
import boto3
import json
import os
from datetime import datetime

reddit = praw.Reddit(
    client_id=os.environ['REDDIT_CLIENT_ID'],
    client_secret=os.environ['REDDIT_CLIENT_SECRET'],
    user_agent="aws-sentiment-analyzer/1.0 (reddit_collector lambda)"
)

s3 = boto3.client('s3')

SUBREDDIT = os.environ.get('SUBREDDIT', 'technology')
POST_LIMIT = int(os.environ.get('POST_LIMIT', '100'))


def lambda_handler(event, context):
    subreddit = reddit.subreddit(SUBREDDIT)
    hot_posts = subreddit.hot(limit=POST_LIMIT)

    posts = []
    for post in hot_posts:
        posts.append({
            'id': post.id,
            'subreddit': SUBREDDIT,
            'text': (post.title + " " + post.selftext).strip(),
            'created_utc': post.created_utc,
            'score': post.score,
            'num_comments': post.num_comments,
            'permalink': post.permalink,
        })

    filename = f"reddit_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

    s3.put_object(
        Bucket=os.environ['S3_BUCKET'],
        Key=f"raw_data/reddit/{filename}",
        Body=json.dumps(posts),
        ContentType='application/json',
    )

    return {
        'statusCode': 200,
        'body': json.dumps(f'Collected {len(posts)} posts from r/{SUBREDDIT}')
    }
