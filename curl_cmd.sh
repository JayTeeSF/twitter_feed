#curl -X POST 'https://api.twitter.com/2/tweets/search/stream/rules' \
#-H "Content-type: application/json" \
#-H "Authorization: Bearer $APP_ACCESS_TOKEN" -d \
#'{
#  "add": [
#    {"value": "cat has:images", "tag": "cats with images"}
#  ]
#}'

curl -X GET -H "Authorization: Bearer $APP_ACCESS_TOKEN" "https://api.twitter.com/2/tweets/search/stream?tweet.fields=created_at&expansions=author_id&user.fields=created_at"

