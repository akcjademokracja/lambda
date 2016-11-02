request = require 'request'


opts = {
  json: {
    text: "GZZZZ",
    channel: "#naszademokracja",
    as_user: false,
    username: "akcjabot"
    }
    
  }
url = "https://hooks.slack.com/services/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"
request.post url, opts, (err, data) ->
  console.log err
  console.log JSON.stringify(data)
