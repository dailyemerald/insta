express = require 'express'
http = require 'http'
fs = require 'fs'
credentials = require './credentials'
request = require 'request'
ParseLib = require('parse-api').Parse

parse = new ParseLib credentials.parse.appID, credentials.parse.masterKey

app = express.createServer()
server = app.listen 11000 #todo: move to env
io = require('socket.io').listen server
io.set 'log level', 1

app.configure ->
  app.set 'views', __dirname + '/views'
  app.set 'view engine', 'jade'
  app.use express.logger("dev")
  app.use express.static(__dirname + "/public")
  app.use express.bodyParser()
  app.use express.cookieParser()
  app.use express.session({ secret: 'super secret'})
  app.use express.methodOverride()
  app.use express.errorHandler({showStack: true, dumpExceptions: true})


#start route stuff. should this be somewhere else?

makeRandomID = ->
  text = ""
  possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  for i in [0..9]
    text += possible.charAt(Math.floor(Math.random() * possible.length))
  text

listSubscriptions = (callback) ->
  requestObj = {
    url: "https://api.instagram.com/v1/subscriptions?client_secret=" + credentials.instagram.client_secret + "&client_id=" + credentials.instagram.client_id
  }
  request requestObj, (error, response, body) ->
    callback JSON.parse body

buildSubscription = (builder, subscriptionCallback) ->
  requestObj = {
    method: 'POST',
    url: 'https://api.instagram.com/v1/subscriptions/',
    form: {
      'title': builder.title,
      'permalink': builder.permalink,
      'client_id': credentials.instagram.client_id, 
      'client_secret': credentials.instagram.client_secret,
      'object': 'geography',
      'aspect': 'media', 
      'lat': builder.lat,
      'lng': builder.lng,
      'radius': builder.radius,
      'callback_url': 'http://insta.dailyemerald.com/notify/' + builder.streamID, #todo: get this out of hardcoding
    }
  }
  #console.log 'buildSub rO', requestObj
  request requestObj, (error, response, body) ->
    #console.log 'error', error
    #console.log 'body', body
    #console.log ' *** '
    if error is null
      # register any of these here?
      #console.log 'debug:', body
      # add to parse?!
      body = JSON.parse body
      dbObject = {
        streamID: builder.streamID,
        instagram: body.data,
        lat: builder.lat,
        lng: builder.lng,
        radius: builder.radius,
        user: builder.user
      }
      if not builder.user?
        console.log 'no user! danger!'
        subscriptionCallback 'no user', null
        return
        
      parse.find 'Users', {user: builder.user}, (err, userResponse) ->
        if userResponse.results.length > 0
          newUser = userResponse.results[0]
          
          console.log 'Found the user object:', newUser
          newUser.streams.push builder.streamID
          console.log 'After push', newUser
          
          parse.update 'Users', {user: newUser.user}, newUser, (err, userUpdateResponse) ->
            console.log 'user update response:', userUpdateResponse
          #append to user
        else
          userObj = {
            user: builder.user,
            streams: [ 'temp' ]
          }
          parse.insert 'Users', userObj, (err, response) ->
            console.log 'Built new user object:', userObj, ' :: response:', response
      
                    
      parse.insert 'Streams', dbObject, (err, response) ->
        console.log 'parse response on Stream insert', response
        subscriptionCallback null, {instagram: body, parse: response}
      
    else
      subscriptionCallback 'Error with buildSubscription!', null

getMedia = (geographyID, callback) ->
  console.log 'getMedia lookup up', geographyID
  requestObj = {
    url: "https://api.instagram.com/v1/geographies/" + geographyID + "/media/recent?client_id=" + credentials.instagram.client_id
  }
  request requestObj, (error, response, body) ->
    if not error and response.statusCode is 200 #todo: does this need to be more robust
      callback null, body #err, data
    else 
      callback body, null #err, data

###

  ROUTES

###

app.all '/notify/:id', (req, res) -> # receives the real-time notification from IG
    if req.query and req.query['hub.mode'] is 'subscribe' #this only happens when the subscription is first built
      console.log 'confirming new subscription...'
      res.send req.query['hub.challenge'] #should probably check this. then add it to the db lookup...?
      return
      
    notifications = req.body
    console.log 'notification for', req.params.id, 'had', notifications.length, 'items'
    for notification in notifications
      getMedia notification.object_id, (err, data) ->
        res.send data

app.get '/', (req, res) ->
  res.render 'index.jade'
  
app.get '/start', (req, res) ->
  res.redirect "https://api.instagram.com/oauth/authorize/?client_id=" + credentials.instagram.client_id + "&redirect_uri=" + credentials.instagram.callback_uri + "&response_type=code"

#app.get '/media/:geographyID', (req, res) ->
#  getMedia req.params.geographyID, (err, data) ->
#    res.send data

app.get '/delete/:subscriptionID', (req, res) ->
  console.log 'got delete request for', req.params.subscriptionID
  requestObj = {
    url: 'https://api.instagram.com/v1/subscriptions?client_secret=' + credentials.instagram.client_secret + '&id=' + req.params.subscriptionID + '&client_id=' + credentials.instagram.client_id,
    method: 'DELETE'
  }
  request requestObj, (error, response, body) ->    
    body = JSON.parse body
    if body.meta.code is 200
      res.redirect '/manage'
    else 
      res.json body

app.get '/authorize', (req, res) ->  
  code = req.query.code
  requestObj = {
    method: 'POST',
    url: 'https://api.instagram.com/oauth/access_token',
    form: {
      'client_id': credentials.instagram.client_id, 
      'client_secret': credentials.instagram.client_secret,
      'grant_type': 'authorization_code', 
      'redirect_uri': credentials.instagram.redirect_uri,
      'code': code
    }
  }
  
  if code    
    request requestObj, (error, response, body) ->    
      #console.log 'error', error
      #console.log 'body', body
      #console.log ' *** '     
      if error is null
        body = JSON.parse body
        if body.user and body.user.id
          req.session.user = body.user
          res.redirect '/manage'
        else
          res.send 'Oops!'
      else
        res.send 'Something has gone horribly wrong. <a href="/start">Try again?</a>'   
  else
    res.send 'oops! you gotta allow us for this to work'  

app.get '/manage', (req, res) ->
  user = req.session.user
  console.log 'user object', user
  if user?
    listSubscriptions (subscriptions) ->
      console.log JSON.stringify subscriptions
      res.render 'manage.jade', {user: user, subscriptions: subscriptions.data }
  else 
    res.redirect '/start'


app.get '/build_test', (req, res) ->
  if req.session? and req.session.user? and req.session.user.username?
    user = req.session.user.username
    console.log 'got a user', user
  else
    res.redirect '/manage'
    
  buildObj = {  
    title: 'test title',
    permalink: 'lovely',
    lat: '44.045494', 
    lng:'-123.074598', 
    radius: '4000', 
    streamID: makeRandomID(),
    user: user
  }
  console.log 'build_test', buildObj
  buildSubscription buildObj, (err, data) -> #4km around UO campus
    if err?
      res.send 'err', err
    else
      res.send 'data', data

app.get '/logout', (req, res) ->
  req.session.destroy (err) ->
    res.send 'logged out!' #todo: render



#socket io stuff
#io.sockets.on 'connection', (socket) ->
#  console.log 'socket connection'