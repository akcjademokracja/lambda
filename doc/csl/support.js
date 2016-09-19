'use strict';
var https = require("https")
console.log('Loading function');

exports.handler = function (event, context) {
   console.log('Running event');
   if (typeof event.Records !== 'undefined') {
       SendMessage(event.Records[0].Sns.Message, function (status) {
           context.done(null, status);
       });  
   }
   else {
       context.done(null, 0);
   }
};function SendMessage(message, completedCallback) {
   var body = message;
   var options = {
       host: 'id.38degrees.org.uk',
       port: 443,
       path: '/api/mailings/feedback-loop',
       method: 'POST',
       headers: {
           'Content-Type': 'application/json',
           'Content-Length': body.length
       }
   };
   
   var req = https.request(options, function (res) {
       res.setEncoding('utf-8');
       var responseString = '';
       res.on('data', function (data) {
           responseString += data;
       });
       res.on('end', function () {
           console.log('Response: ' + responseString);
           completedCallback('API request sent successfully.');
       });
   });
   req.on('error', function (e) {
       console.error('HTTP error: ' + e.message);
       completedCallback('API request completed with error(s).');
   });
   console.log('Making API call');
   req.write(body);
   req.end();}
