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
  civi_endpoint: process.env['CIVI_API'],
  civi_events: {'ND Petition': 70, 'ND Event': 69}
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
          return Promise.all msg_list.map (msg) =>
            console.log "emit: #{msg.Body}"
            body = JSON.parse(msg.Body)
            @emitter.emit(body).then @delete(msg)
        else
          console.log "no messages to process"
          return []
      .catch (error) =>
        console.error "Error processing msgs #{error}"
        ok error
        

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
      console.log "[Civi] => #{entity}.#{action}(#{opts.qs.json})"
      handle_response = (err, status, body) =>
        if err
          fail err
        else
          console.log "[Civi] <= #{body}"
          data = JSON.parse body
          if data.is_error > 0
            fail "Civi API call error body:#{body}"
          else
            ok data.values


      if action == 'get'
        request.get @endpoint, opts, handle_response
      else
        request.post @endpoint, opts, handle_response


  petition_external_id: (petition, type="petition") ->
    # 32 character limit.
    # MD5->Base64 = 24 bytes, leaving 8.
    "nd:csl:" + Crypto.enc.Base64.stringify(Crypto.MD5("#{type}:#{petition.slug}"))

  civi_campaign_slug: (petition, type="petition") ->
    code={petition:"P",event:"E"}
    "ND#{code[type]}-#{petition.slug}"

  civi_campaign_title: (petition, type="petition") ->
    title={petition:"Petition",event:"Event"}
    "ND #{title[type]} #{petition.title}"

  civi_campaign_hash: (petition, type="petition") ->
    {
      name: @civi_campaign_slug(petition, type),
      title: @civi_campaign_title(petition, type),
      description: "#{petition.url}"
    }


  get_campaign: (what, type) ->
    external_id = @petition_external_id(what, type)
    return @api('Campaign', 'get', {external_identifier: external_id})

  create_or_update_petition: (message) ->
    petition = message.data 
    entity_type = message.type.split('.')[0]
    external_id = @petition_external_id petition, entity_type
    return @api('Campaign', 'get', {external_identifier: external_id})
      .then (civi_campaigns) =>
        if civi_campaigns.length == 0
          console.log "no campaign with this external id"
          cc_data = @civi_campaign_hash(petition, entity_type)
          cc_data.external_identifier = external_id
          return @api('Campaign', 'create', cc_data)
        else
          cc = civi_campaigns[0]
          console.log "there is a campaign: #{cc.title} (#{cc.id})"
          if cc.title != @civi_campaign_slug(petition, entity_type)
            cc_data = @civi_campaign_hash(petition, entity_type)
            cc_data.id = cc.id
            return @api('Campaign', 'create', cc_data)
          else
            return cc      

  create_or_update_member: (member) ->
    console.log "UPSERT MEM: #{JSON.stringify(member)}"
    got_contact = @api('Contact', 'get', {email: member.email})
      .then (contacts) =>
        if contacts.length > 0
          console.log "Found #{contacts.length} members for #{member.email}"
          contact = contacts[0]
          console.log "Will update #{contact.first_name} #{contact.last_name} (#{contact.postal_code})"
          return contact
        else          
          @api('Contact', 'create', {
            contact_type: 'Individual',
            first_name: member.first_name,
            last_name: member.last_name,
            })
            .then (new_contacts) =>
              new_contact = new_contacts[0]
              console.log "new member: #{JSON.stringify(new_contact)}"
              new_contact

    # proactively update the postcode and email
    got_contact.then (contact) =>
      console.log "Contact's email_id=#{contact.email_id} address_id=#{contact.address_id}"
      email_hash = {, email: member.email }
      if contact.email_id?
        email_hash.id = contact.email_id
        email_hash.contact_id = contact.id
      else
        email_hash.contact_id = contact.id
        
      create_email = @api('Email', 'create', email_hash)

      address_hash = {postal_code: member.postcode, country_id: member.country, location_type_id: "Główna"}
      if contact.address_id?
        address_hash.id = contact.address_id
      else
        address_hash.contact_id = contact.id
      
      create_address = @api('Address', 'create', address_hash)
      
      return Promise.all([create_email, create_address])
        .then (done) =>
          console.log "Creating email/addr: #{JSON.stringify(done)}"
          contact # let's return the new contact anyway
          
  member_activity: (member, activity_hash) ->
    duplicates_present = @api('ActivityContact', 'get', {
      'activity_id.activity_date_time': activity_hash.activity_date_time,
      'contact_id.id': member.id,
      'activity_id.campaign_id': activity_hash.campaign_id,
      'activity_id.activity_type_id': activity_hash.activity_type_id
      }).then (duplicates) =>
        if duplicates.length > 0
          console.log "There are #{duplicates.length} duplicates for this activity. skipping."
          return true
        else
          return @api('Activity', 'create', {
            "campaign_id": activity_hash.campaign_id,
            "api.ActivityContact.create": {"contact_id": member.id},
            "activity_type_id": activity_hash.activity_type_id,
            "activity_date_time": activity_hash.activity_date_time,
            "source_contact_id": member.id,
            "subject": activity_hash.campaign_subject,
            "location": "naszademokracja.pl:#{activity_hash.campaign_type}"
            }).then (activities) => activities[0]

  civi_datetime: (d) ->
    date = new Date(d)
    date.toJSON()

  add_attendee: (message) ->
    get_member = @create_or_update_member(message.data)
    get_campaign = @get_campaign(message.data.event, 'event')
    Promise.all([get_member, get_campaign])
      .then ([member, campaigns]) =>
        activity_hash = {
          activity_type_id: 'NDEvent',
          activity_date_time: @civi_datetime(message.data.created_at),
          campaign_id: campaigns[0].id,
          campaign_subject: @civi_campaign_slug(message.data.event, 'event'),
          campaign_type: 'event'

          }
        @member_activity(member, activity_hash)

  add_signature: (message) ->
    get_member = @create_or_update_member(message.data)
    get_campaign = @get_campaign(message.data.petition, 'petition')
    Promise.all([get_member, get_campaign])
      .then ([member, campaigns]) =>
        activity_hash = {
          activity_type_id: 'NDPetition',
          activity_date_time: @civi_datetime(message.data.last_signed_at),
          campaign_id: campaigns[0].id,
          campaign_subject: @civi_campaign_slug(message.data.petition, 'petition'),
          campaign_type: 'petition'
        }
        @member_activity(member, activity_hash)

  unsubscribe: (message) ->
    get_member = @create_or_update_member(message.data)
    get_member.then (contact) =>
      console.log "Opting Out #{contact.first_name} #{contact.last_name} <#{contact.email}>"
      @api('Contact', 'create', {id: contact.id, contact_type: 'Individual', is_opt_out: 1})

            
  emit: (message) ->
    console.log "Civi: message type: #{message.type}"
    switch message.type
      when "petition.launched" then @create_or_update_petition(message)
      when "petition.updated" then @create_or_update_petition(message)
      when "event.created" then @create_or_update_petition(message)
      when "event.updated" then @create_or_update_petition(message)
      when "attendee.created" then @add_attendee(message)
      when "attendee.updated" then @add_attendee(message)
      when "signature.created" then @add_signature(message)
      when "signature.confirmed" then true #ignore, for now.
      #when "signature.deleted" then false  # TODO
      when "unsubscribe.created" then @unsubscribe(message)
      else throw "slack emitter does not support type #{message.type}"

                                
slack = new Slack Config.slack_bot, '#naszademokracja'
slack_poll = new Poll Config.slack_queue, slack

civi = new Civi Config.civi_endpoint, Config.civi_site_key, Config.civi_user_key
civi_poll = new Poll Config.civi_queue, civi


exports.event = (event, context, callback) ->
  # if event != {}
  #   console.log "~~~ TESTING MODE ~~~"
  #   civi.emit event
  #   return
  
  ok = (x) -> callback(null)
  fail = (err) -> callback(err)
  Promise.all([slack_poll.process(), civi_poll.process()]).then(ok).catch(fail)
