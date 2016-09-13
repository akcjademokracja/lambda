// Generated by CoffeeScript 1.4.0
(function() {
  var AWS, Config, HTTP, Lambda, PROCESS_MESSAGE, Poll, Promise, Slack, bluebird, poll, querystring, request, slack, sqs;

  querystring = require('querystring');

  AWS = require('aws-sdk');

  bluebird = require('bluebird');

  Promise = bluebird.Promise;

  AWS.config.setPromisesDependency();

  HTTP = require('http');

  request = require('request');

  sqs = new AWS.SQS({
    refion: 'us-west-1'
  });

  Lambda = new AWS.Lambda();

  PROCESS_MESSAGE = 'process-message';

  Config = {
    civi_queue: process.env['CIVI_QUEUE'],
    slack_queue: process.env['SLACK_QUEUE'],
    slack_bot: process.env['SLACK_BOT']
  };

  Poll = (function() {

    function Poll(queue_url, emitter) {
      this.queue = queue_url;
      this.emitter = emitter;
    }

    Poll.prototype.fetch = function() {
      var params,
        _this = this;
      params = {
        QueueUrl: this.queue,
        MaxNumberOfMessages: 10,
        VisibilityTimeout: 15
      };
      return new Promise(function(ok, fail) {
        return sqs.receiveMessage(params, function(err, data) {
          console.log("Omg! received messages " + err + ": " + (JSON.stringify(data)));
          if (err) {
            return fail(err);
          } else {
            return ok(data.Messages);
          }
        });
      });
    };

    Poll.prototype["delete"] = function(message) {
      var params,
        _this = this;
      params = {
        QueueUrl: this.queue,
        ReceiptHandle: message.ReceiptHandle
      };
      return new Promise(function(ok, fail) {
        return sqs.deleteMessage(params, function(err) {
          if (err) {
            return fail(err);
          } else {
            return ok(null);
          }
        });
      });
    };

    Poll.prototype.process = function(ok, fail) {
      var _this = this;
      return this.fetch().then(function(msg_list) {
        console.log("got to processing messages list: " + (msg_list || []).length);
        if (msg_list != null) {
          return Promise.all(msg_list.map(function(msg) {
            var body;
            console.log("emit: " + msg.Body);
            body = JSON.parse(msg.Body);
            return _this.emitter.emit(body).then(_this["delete"](msg));
          }));
        } else {
          return [];
        }
      })["catch"](function(error) {
        return fail(error);
      });
    };

    return Poll;

  })();

  Slack = (function() {

    function Slack(webhook, channel) {
      this.webhook = webhook;
      this.channel = channel;
    }

    Slack.prototype.say = function(what) {
      var data,
        _this = this;
      console.log("Saying " + what);
      data = {
        channel: this.channel,
        text: what,
        as_user: false,
        username: "akcjabot"
      };
      return new Promise(function(ok, fail) {
        var opts;
        opts = {
          json: data
        };
        return request.post(Config.slack_bot, opts, function(err, status, body) {
          console.log("HTTP " + status + "; opts: " + opts + "; body: " + body);
          if (err) {
            return fail(err);
          } else {
            return ok(body);
          }
        });
      });
    };

    Slack.prototype.petition_flagged = function(petition) {
      var link;
      link = function(url) {
        return "<a href=\"" + url + "\">" + url + "</a>";
      };
      return this.say("Kampania `" + petition.title + "' została oznaczona do moderacji " + petition.url + ".");
    };

    Slack.prototype.petition_launched = function(petition) {
      var link;
      link = function(url) {
        return "<a href=\"" + url + "\">" + url + "</a>";
      };
      return this.say("Nowa kampania `" + petition.title + "' " + petition.url + ".");
    };

    Slack.prototype.emit = function(message) {
      switch (message.type) {
        case "petition.launched":
          return this.petition_launched(message.data);
        case "petition.flagged":
          return this.petition_flagged(message.data);
        default:
          throw "slack emitter does not support type " + message.type;
      }
    };

    return Slack;

  })();

  slack = new Slack(Config.slack_bot, '#naszademokracja');

  poll = new Poll(Config.slack_queue, slack);

  exports.event = function(event, context, callback) {
    var fail, ok;
    ok = function(x) {
      return callback(null);
    };
    fail = function(err) {
      return callback(err);
    };
    return poll.process(ok, fail);
  };

}).call(this);
