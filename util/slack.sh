#!/bin/bash

#https://slack.com/api/api.test


#token=xoxb-67658865252-R1o8xGsNa7qYT11UOSjLAQGN
hook=https://hooks.slack.com/services/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

sa()
{
#  call=$1
#  shift
#  params=$1
    #  shift
  params=""
  while [[ $# -gt 0 ]]; do
      if [ -n "$params" ]; then params="$params, "; fi
      params="$params\"$1\": \"$2\""; shift; shift;
  done     
  #curl --data-urlencode "token=${token}&as_user=false&username=akcjabot&$params"  https://slack.com/api/$call
  echo "{$params}"
  curl -d "payload={$params}" $hook
}



#sa api.test "name=random"
#sa channels.join name=random

#sa chat.postMessage channel=random "text=blurp. wrRRrpr. zzZZzz.."

sa channel '#general'  text "blurp. wrRRrpr. zzZZzz.."
