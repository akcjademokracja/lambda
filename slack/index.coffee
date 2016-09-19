querystring = require 'querystring'
AWS = require 'aws-sdk'
bluebird = require 'bluebird'
Promise = bluebird.Promise
AWS.config.setPromisesDependency();

HTTP = require 'http'
request = require 'request'
Crypto = require 'crypto-js'

sqs = new AWS.SQS({refion: 'us-west-1'})
Lambda = new AWS.Lambda();

PROCESS_MESSAGE = 'process-message';

Config = {
  civi_queue: process.env['CIVI_QUEUE'],
  slack_queue: process.env['SLACK_QUEUE'],
  slack_bot: process.env['SLACK_BOT'],
  civi_site_key: process.env['CIVI_SITE_KEY'],
  civi_user_key: process.env['CIVI_USER_KEY'],
  civi_endpoint: process.env['CIVI_API']
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
    console.log "DELETE message #{message.ReceiptHandle}"
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
      request.post @webhook, opts, (err, status, body) =>
        if err
          fail err
        else
          ok body

  petition_flagged: (petition) ->
    #link = (url) -> "<a href=\"#{url}\">#{url}</a>"
    @say "Kampania _#{petition.title}_ została oznaczona do moderacji #{petition.url}."

  petition_launched: (petition) ->
    @say "Nowa kampania _#{petition.title}_ #{petition.url}."

  petition_updated: (petition) ->
    @say "Zmiana w kampanii _#{petition.title}_ #{petition.url}."

  blast_created: (blast) ->
    @say "Nowy blast: _#{blast.subject}_ od #{blast.from_name} <#{blast.from_address}>"
    
  event_created: (event) ->
    @say "Nowe wydarzenie: _#{event.title}_ #{event.url}"

  event_updated: (event) ->
    @say "Zmiana wydarzenia: _#{event.title}_ #{event.url}"

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


class Civi
  constructor: (endpoint, site_key, user_key) ->
    @endpoint = endpoint
    @key = site_key
    @api_key = user_key

  api: (entity, action, params) ->
    new Promise (ok, fail) =>
      params.sequential = 1
      opts = {
        qs: {
          key: @key,
          api_key: @api_key,
          entity: entity,
          action: action,
          json: JSON.stringify(params)
          }
      }
      request.get @endpoint, opts, (err, status, body) =>
        if err
          fail err
        else
          console.log "CIVI API: #{body}"
          data = JSON.parse body
          if data.is_error > 0
            fail "Civi API call error body:#{body}"
          else
            ok data

  petition_external_id: (petition) ->
    # 32 character limit.
    # MD5->Base64 = 24 bytes, leaving 8.
    "nd:csl:" + Crypto.enc.Base64.stringify(Crypto.MD5("petition:#{petition.slug}"))

  civi_campaign_slug: (petition) ->
    "ND_#{petition.slug}"

  civi_campaign_title: (petition) ->
    "ND #{petition.title}"

  civi_campaign_hash: (petition) ->
    {
      external_identifier: @petition_external_id(petition),
      name: @civi_campaign_slug(petition),
      title: @civi_campaign_title(petition)
    }

  create_or_update_petition: (petition) ->
    external_id = @petition_external_id petition
    return @api('Campaign', 'get', {external_identifier: external_id})
      .then (civi_campaigns) =>
        if civi_campaigns.values.length == 0
          console.log "no campaign with this external id"
          cc_data = @civi_campaign_hash(petition)
          return @api('Campaign', 'create', cc_data)
        else
          cc = civi_campaigns[0]
          console.log "there is a campaign: #{cc.title} (#{cc.id})"
          if cc.title != @civi_campaign_slug(petition)
            cc_data = @civi_campaign_hash(petition)
            cc_data.id = cc.id
            return @api('Campaign', 'create', cc_data)
          else
            return cc      
          
    
  emit: (message) ->
    console.log "Civi: message type: #{message.type}"
    switch message.type
      when "petition.launched" then @create_or_update_petition(message.data)
      else throw "slack emitter does not support type #{message.type}"

                                
slack = new Slack Config.slack_bot, '#naszademokracja'
slack_poll = new Poll Config.slack_queue, slack

civi = new Civi Config.civi_endpoint, Config.civi_site_key, Config.civi_user_key
civi_poll = new Poll Config.civi_queue, civi

# exports.event = (event, context, callback) ->
#   civi.api('Contact', '', { id: -13529123 })
#     .then (data) ->
#       console.log "mamy to! #{JSON.stringify(data)}"
#       callback null
#     .catch (err) ->
#       console.log "błąd #{err}"
#       callback err.error_message


exports.event = (event, context, callback) ->
  ok = (x) -> callback(null)
  fail = (err) -> callback(err)
  #poll.process ok, fail
  civi_poll.process ok, fail
