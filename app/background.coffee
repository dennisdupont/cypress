Promise = require("bluebird")
pick    = require("lodash/pick")

HOST = "CHANGE_ME_HOST"
PATH = "CHANGE_ME_PATH"

firstOrNull = (cookies) ->
  ## normalize into null when empty array
  cookies[0] ? null

connect = (host, path, io) ->
  io ?= global.io

  ## bail if io isnt defined
  return if not io

  fail = (id, err) ->
    client.emit("automation:response", id, {
      __error: err.message
      __stack: err.stack
      __name:  err.name
    })

  invoke = (method, id, args...) ->
    respond = (data) ->
      client.emit("automation:response", id, {response: data})

    Promise.try ->
      automation[method].apply(automation, args.concat(respond))
    .catch (err) ->
      fail(id, err)

  ## cannot use required socket here due
  ## to bug in socket io client with browserify
  client = io.connect(host, {path: path})

  client.on "automation:request", (id, msg, data) ->
    switch msg
      when "get:cookies"
        invoke("getCookies", id, data)
      when "get:cookie"
        invoke("getCookie", id, data)
      when "set:cookie"
        invoke("setCookie", id, data)
      when "clear:cookies"
        invoke("clearCookies", id, data)
      when "clear:cookie"
        invoke("clearCookie", id, data)
      when "focus:browser:window"
        invoke("focus", id)
      else
        fail(id, {message: "No handler registered for: '#{msg}'"})

  client.on "connect", ->
    client.emit("automation:connected")

  return client

## initially connect
connect(HOST, PATH, global.io)

automation = {
  connect: connect

  getUrl: (cookie = {}) ->
    prefix = if cookie.secure then "https://" else "http://"
    prefix + cookie.domain + cookie.path

  clear: (filter = {}) ->
    clear = (cookie) =>
      new Promise (resolve, reject) =>
        url = @getUrl(cookie)
        chrome.cookies.remove {url: url, name: cookie.name}, (details) ->
          if details
            resolve(cookie)
          else
            reject(chrome.runtime.lastError)

    @getAll(filter)
    .map(clear)

  getAll: (filter = {}) ->
    get = ->
      new Promise (resolve) ->
        chrome.cookies.getAll(filter, resolve)

    get()

  getCookies: (filter, fn) ->
    @getAll(filter)
    .then(fn)

  getCookie: (filter, fn) ->
    @getAll(filter)
    .then(firstOrNull)
    .then(fn)

  setCookie: (props = {}, fn) ->
    set = =>
      new Promise (resolve, reject) =>
        props.url = @getUrl(props)
        chrome.cookies.set props, (details) ->
          if details
            resolve(details)
          else
            reject(chrome.runtime.lastError)

    set()
    .then(fn)

  clearCookie: (filter, fn) ->
    @clear(filter)
    .then(firstOrNull)
    .then(fn)

  clearCookies: (filter, fn) ->
    @clear(filter)
    .then(fn)

  focus: (fn) ->
    ## lets just make this simple and whatever is the current
    ## window bring that into focus
    ##
    ## TODO: if we REALLY want to be nice its possible we can
    ## figure out the exact window that's running Cypress but
    ## that's too much work with too little value at the moment
    chrome.windows.getCurrent (window) ->
      chrome.windows.update window.id, {focused: true}, ->
        fn()
}

module.exports = automation