querystring = require 'querystring'
AWS = require 'aws-sdk'
bluebird = require 'bluebird'
Promise = bluebird.Promise
AWS.config.setPromisesDependency();

HTTP = require 'http'
request = require 'request'
sqs = new AWS.SQS({refion: 'us-west-1'})
Lambda = new AWS.Lambda();

PROCESS_MESSAGE = 'process-message';

Config = {
  civi_queue: process.env['CIVI_QUEUE'],
  slack_queue: process.env['SLACK_QUEUE'],
  slack_bot: process.env['SLACK_BOT']
}

class Poll
  constructor: (queue_url, emitter) ->
    @queue = queue_url
    @emitter = emitter

  fetch:  ->
    params = {
      QueueUrl: @queue,
      MaxNumberOfMessages: 10,
      VisibilityTimeout: 15
    }
    new Promise (ok, fail) =>
      sqs.receiveMessage params, (err, data) =>
        console.log "Omg! received messages #{err}: #{JSON.stringify(data)}"
        if err
          return fail(err)
        else
          ok data.Messages

  delete: (message) ->
    params = {
      QueueUrl: @queue,
      ReceiptHandle: message.ReceiptHandle
      }
    new Promise (ok, fail) =>
      sqs.deleteMessage params, (err) =>
        if err
          fail err
        else
          ok null

  process: (ok, fail) ->
    @fetch()
      .then (msg_list) =>
        console.log "got to processing messages list: #{(msg_list or []).length}"
        if msg_list?
          Promise.all msg_list.map (msg) =>
            console.log "emit: #{msg.Body}"
            body = JSON.parse(msg.Body)
            @emitter.emit(body).then @delete(msg)
        else
          []
      .catch (error) =>
        fail(error)
        

class Slack
  constructor: (webhook, channel) ->
    @webhook = webhook
    @channel = channel

  say: (what) ->
    console.log "Saying #{what}"
    data = {
      channel: @channel,
      text: what,
      as_user: false,
      username: "akcjabot"
      }

    new Promise (ok, fail) =>
      opts = {
        json: data
        }
      request.post Config.slack_bot, opts, (err, status, body) =>
        console.log "HTTP #{status}; opts: #{opts}; body: #{body}"
        if err
          fail err
        else
          ok body

  petition_flagged: (petition) ->
    link = (url) -> "<a href=\"#{url}\">#{url}</a>"
    @say "Kampania `#{petition.title}' została oznaczona do moderacji #{petition.url}."

  petition_launched: (petition) ->
    link = (url) -> "<a href=\"#{url}\">#{url}</a>"
    @say "Nowa kampania `#{petition.title}' #{petition.url}."
    

  emit: (message) ->
    switch message.type
      when "petition.launched" then @petition_launched(message.data)
      when "petition.flagged" then @petition_flagged(message.data)
      else throw "slack emitter does not support type #{message.type}"
  
slack = new Slack Config.slack_bot, '#naszademokracja'
poll = new Poll Config.slack_queue, slack

exports.event = (event, context, callback) ->
  ok = (x) -> callback(null)
  fail = (err) -> callback(err)
  poll.process ok, fail
