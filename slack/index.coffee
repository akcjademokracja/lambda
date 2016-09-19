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
    console.log "Poll queue #{@queue}"
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
        if msg_list?
          console.log "Processing #{msg_list.length} events"
          Promise.all msg_list.map (msg) =>
            console.log "emit: #{msg.Body}"
            body = JSON.parse(msg.Body)
            @emitter.emit(body).then @delete(msg)
        else
          console.log "no messages to process"
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
    #link = (url) -> "<a href=\"#{url}\">#{url}</a>"
    @say "Kampania `#{petition.title}' została oznaczona do moderacji #{petition.url}."

  petition_launched: (petition) ->
    @say "Nowa kampania `#{petition.title}' #{petition.url}."

  petition_updated: (petition) ->
    @say "Zmiana w kampanii `#{petition.title}' #{petition.url}."

  blast_created: (blast) ->
    @say "Nowy blast: `#{blast.subject}' od #{blast.from_name} <#{blast.from_address}>"
    
  event_created: (event) ->
    @say "Nowe wydarzenie: `#{event.title}' #{event.url}"

  event_updated: (event) ->
    @say "Zmiana wydarzenia: `#{event.title}' #{event.url}"

  emit: (message) ->
    switch message.type
      when "petition.launched" then @petition_launched(message.data)
      when "petition.launched.ham" then @petition_launched(message.data)
      when "petition.launched.requires_moderation" then @petition_launched(message.data)
      when "petition.flagged" then @petition_flagged(message.data)
      when "blast_email.created" then @blast_created(message.data)
      when "event.created" then @event_created(message.data)
      when "event.updated" then @event_updated(message.data)
      when "petition.updated" then @petition_updated(message.data)
      when "petition.updated.requires_moderation" then @petition_updated(message.data)
      else throw "slack emitter does not support type #{message.type}"
  
slack = new Slack Config.slack_bot, '#naszademokracja'
poll = new Poll Config.slack_queue, slack

exports.event = (event, context, callback) ->
  ok = (x) -> callback(null)
  fail = (err) -> callback(err)
  poll.process ok, fail
