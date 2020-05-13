# Lab session #4: Moving to the cloud


This Lab assignment is built on top of the previous ones to discuss a basis for extracting appealing terms from a dataset of tweets while we “keep the connection open” and gather all the upcoming tweets about a particular event.

* [Task 3.1: Realtime tweets API of Twitter](#Tasks31)
* [Task 3.2: Analyzing tweets - counting terms](#Tasks32)  
* [Task 3.3: Case study](#Tasks33)  
* [Task 3.4: Student proposal](#Tasks34)  

#  Tasks for Lab session #3

<a name="Tasks31"/>

## Task 3.1: Detach your storage

If our Twitter listener stops working we don't want to loose the data captured.
We may also want to have several listeners running at the same time and keep all their data stored to be analyzed.

S3 provides an unexpensive permanent storage that can coneniently be accessed by any other AWS component.

Install boto3 to access the AWS functionalities from Python.

````bash
conda install boto3
````

Go to AWS S3 console and create a new bucket named `team-00.upc.accenture` using your team number.

Create a new file named `TwitterListenerS3.py` that will write the tweets to the S3 bucket.

Create the `writeTweet` function 
````python
def writeTweet(bucket, hashtag, data):
    tweet = json.loads(data)
    s3 = boto3.resource('s3', aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
    s3.Object(bucket, '%s/%s.json'%(hashtag, tweet['id_str'])).put(Body=data)
````
Use it in the tweeter listener
````python
class MyListener(StreamListener):
    
    def __init__(self, bucket, hashtag):
        self.bucket = bucket
        self.hashtag = hashtag


    def on_data(self, data):
        try:
            writeTweet(self.bucket, self.hashtag, data)
        except BaseException as e:
            print("Error on_data: %s" % str(e))
        return True

    def on_error(self, status):
        print(status)
        return True

````
Invoke the listener using the name of the bucket that you have created above.
````python
twitter_stream = Stream(auth, MyListener('team-00.upc.accenture', my_hashtag))
````

Leave it running for some minutes and go to S3 console and see how tweets are being stored there. 

Q311: Add the code to `TwitterListenerS3.py and your comments to README.md. Add a screen capture of your S3 bucket containing some tweets.


We can now move the listener to the Cloud.

https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:879370021840:applications~StreamData-IO-Twitter-Search


**Q35: How long have you been working on this session? What have been the main difficulties you have faced and how have you solved them?** Add your answers to `README.md`.


# How to submit this assignment:

Create a **new and private** repo named *https://github.com/YOUR-ACCOUNT-NAME/CLOUD-COMPUTING-CLASS-2020-Lab3* and invite your Lab. session partner and `angeltoribio-UPC-BCN`.

It needs to have, at least, two files `README.md` with your responses to the above questions and `authors.json` with both members email addresses:

```json5
{
  "authors": [
    "FIRSTNAME1.LASTNAME1@accenture.com",
    "FIRSTNAME2.LASTNAME2@accenture.com"
  ]
}
```

1. Link to your dataset created in task 3.4.
2. Add any comment that you consider necessary at the end of the 'README.md' file

Make sure that you have updated your local GitHub repository (using the `git`commands `add`, `commit` and `push`) with all the files generated during this session. 

**Before the deadline**, all team members shall push their responses to their private **CLOUD-COMPUTING-CLASS-2020-Lab3** repository.