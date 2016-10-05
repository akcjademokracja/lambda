
https = require 'https'
AWS = require 'aws-sdk'
sqs = new AWS.SQS({region: 'us-west-1'})

Config = {
  civi_queue: process.env['CIVI_QUEUE'],
  slack_queue: process.env['SLACK_QUEUE'],
  token: process.env['TOKEN'],
  civi_types: [
    "member.deleted",
    "petition.launched",
    "petition.updated",
    "event.created",
    "event.updated",
    "signature.created",
    "signature.deleted",
    "signature.confirmed",
    "unsubscribe.created",
    "attendee.created",
    "attendee.updated"
    ],
  slack_types: [
    "blast_email.created",
    "event.created",
    "event.updated",
    "local_chapter.organiser_request.created",
    "petition.flagged",
    "petition.launched",
    "petition.launched.ham",
    "petition.launched.requires_moderation",
    "petition.reactivated",
    "petition.updated",
    "petition.updated.requires_moderation"
    ]
  }

  # event.params.querystring.token <- where it is passed

d = (o) -> JSON.stringify(o)

class Pile
  constructor: (queue_url, types) ->
    @url = queue_url
    @pile_types = types

  result: (err, data) ->
    console.log("SQS error is #{err}, data is #{d(data)}")
    
  pile: (obj, callback) ->
    sqs.sendMessage({
      MessageBody: JSON.stringify(obj),
      QueueUrl: @url
      }, (err,data) => @result(err,data))

  event: (event, context, callback) ->
    console.log("event: #{d(event)}")
    if event.type in @pile_types      
      @pile(event, callback)
      callback null, true
    else
      callback null, false


civi = new Pile(Config.civi_queue, Config.civi_types)
slack = new Pile(Config.slack_queue, Config.slack_types)

exports.event = (args...) ->
  civi.event(args...)
  slack.event(args...) 
