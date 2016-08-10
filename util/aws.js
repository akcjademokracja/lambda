var AWS = require('aws-sdk');
var sqs = new AWS.SQS({region : 'eu-west-1'});
var http = require('https');var postToSQS = function(data, callback) {
   sqs.sendMessage({
       MessageBody: JSON.stringify(data),
       QueueUrl: 'https://sqs.eu-west-1.amazonaws.com/558694644073/identity'
   }, function(err, data) {
       callback(err, data);
   });
};exports.handler = function(event, context) {
   postToSQS(event,  function(err, data) {
       if (err) {
         console.log('error:', "Error posting to SQS: " + err);
         context.done('error', "Error sending action data");
       } else {
         console.log('Success', 'Action posted');
         context.done(null, '');
       }
   });
};
