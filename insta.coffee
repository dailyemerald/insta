express = require 'express'
http = require 'http'
fs = require 'fs'
credentials = require './credentials'
instagramLib = require 'instagram'
request = require 'request'
#parse = require 'parse-api'

#instagram = new instagramLib.API(credentials.instagram.access_token)

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
  app.use express.methodOverride()
  app.use express.errorHandler({showStack: true, dumpExceptions: true})


#start route stuff. should this be somewhere else?

buildSubscription = (lat, lng, radius, feedIdentifier, subscriptionCallback) ->
  requestObj = {
    method: 'POST',
    url: 'https://api.instagram.com/oauth/access_token',
    form: {
      'client_id': credentials.instagram.client_id, 
      'client_secret': credentials.instagram.client_secret,
      'object': 'geography',
      'aspect': 'media', 
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'callback_url': 'http://insta.dailyemerald.com/notify/' + feedIdentifier, #todo: get this out of hardcoding
    }
  }
  request requestObj, (error, response, body) ->
    console.log 'error', error
    console.log 'body', body
    console.log ' *** '
    if error is null
      # register any of these here?
      console.log 'debug:', body
      subscriptionCallback null, JSON.parse body
    else
      subscriptionCallback 'Error with buildSubscription!', null

###

  ROUTES

###

app.all '/notify/id?', (req, res) -> # receives the real-time notification from IG
    if req.query and req.query['hub.mode'] is 'subscribe' #this only happens when the subscription is first built
      console.log 'Challenge time!'
      res.send req.query['hub.challenge'] #should probably check this. then add it to the db lookup...?
      return
      
    console.log req
    geographyID = getGeographyID('something') #todo: link this to request? how?  
    request_url = "https://api.instagram.com/v1/geographies/" + geographyID + "/media/recent?client_id=" + credentials.instagram.client_id
    request request_url, (error, response, body) ->
      if not error and response.statusCode is 200 #todo: does this need to be more robust
        bodyObj = JSON.parse(body)
        photos = bodyObj.data
        #stuff here
        console.log photos

app.get '/', (req, res) ->
  res.render 'index.jade'

app.get '/start', (req, res) ->
  res.redirect "https://api.instagram.com/oauth/authorize/?client_id="+credentials.instagram.client_id+"&redirect_uri=http://insta.dailyemerald.com/authorize&response_type=code"

app.get '/authorize', (req, res) ->
  
  code = req.query.code
  
  requestObj = {
    method: 'POST',
    url: 'https://api.instagram.com/oauth/access_token',
    form: {
      'client_id': credentials.instagram.client_id, 
      'client_secret': credentials.instagram.client_secret,
      'grant_type': 'authorization_code', 
      'redirect_uri': 'http://insta.dailyemerald.com/authorize', #todo: get this out of hardcoding
      'code': code
    }
  }
  
  if code    
    request requestObj, (error, response, body) ->
      
      console.log 'error', error
      console.log 'body', body
      console.log ' *** '
      
      if error is null
        body = JSON.parse body
        if body.user and body.user.id
          res.session.user = body.user
          res.redirect '/manage'
        else
          res.send 'Oops!'
      else
        res.send 'Something has gone horribly wrong. <a href="/start">Try again?</a>'
    
  else
    res.send 'oops! you gotta allow us for this to work'  

app.get '/manage', (req, res) ->
  res.render 'create.jade'

app.get '/feeds', (req, res) ->
  res.send 'feeds'

#app.get '/logout', (req, res) ->
#  req.session.destroy (err) ->
#    res.send 'logged out!'

app.get '/show_subscriptions', (req, res) ->
  console.log 'hi'
  requestObj = {
    method: "POST",
    url: "https://api.instagram.com/v1/subscriptions?client_secret=" + credentials.instagram.client_secret + "&client_id=" + credentials.instagram.client_id
  }
  console.log requestObj.url
  request requestObj, (error, response, body) ->
    res.send body

#socket io stuff
#io.sockets.on 'connection', (socket) ->
#  console.log 'socket connection'