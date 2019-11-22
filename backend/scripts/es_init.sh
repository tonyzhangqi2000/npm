#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "You must enter elasticsearch url"
fi

ES=$1

curl -XPUT ${ES}/_ingest/pipeline/correct_switched -H 'Content-Type: application/json' -d '
{
    "description": "convert switched fields to date",
    "processors": [
      {
        "date" : {
          "field" : "FIRST_SWITCHED",
          "target_field" : "FIRST_SEEN",
          "formats" : ["UNIX"],
          "timezone" : "Asia/Shanghai"
        }
      },
      {
        "date" : {
          "field" : "LAST_SWITCHED",
          "target_field" : "LAST_SEEN",
          "formats" : ["UNIX"],
          "timezone" : "Asia/Shanghai"
        }
      },
      {
        "remove": {
          "field": ["FIRST_SWITCHED", "LAST_SWITCHED"],
          "ignore_missing": true
        }
      }
    ]
}
'
