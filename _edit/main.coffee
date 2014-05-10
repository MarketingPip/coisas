React = require 'react'
Feed = require 'feed'
Handlebars = require 'handlebars'
Taffy = require 'taffydb'
TextLoad = require './textload.coffee'
GitHub = require './github.coffee'

CommonProcessor = require './processors/common.coffee'
Processors =
  article: require './processors/article.coffee'
  table: require './processors/table.coffee'
  list: require './processors/list.coffee'
  chart: require './processors/chart.coffee'
  graph: require './processors/graph.coffee'

BaseTemplate = 'templates/base.html'
Templates =
  names: [
    'article',
    'table',
    'list',
    'chart',
    'graph',
  ]
  addresses: [
    'templates/article.html',
    'templates/table.html',
    'templates/list.html',
    'templates/chart.html',
    'templates/graph.html',
  ]
Partials =
  names: [
    'related',
    'header',
    'footer',
  ]
  addresses: [
    'templates/related.html'
    'templates/header.html'
    'templates/footer.html'
  ]

# react
{main, aside, article, header, div, ul, li, span,
 table, thead, tbody, tfoot, tr, td, th,
 b, i, a, h1, h2, h3, h4, small,
 form, label, input, select, option, textarea, button} = React.DOM

# github client
gh_data = /([\w-_]+)\.github\.((io|com)\/)([\w-_]*)/.exec(location.href)
if gh_data
  user = gh_data[1]
  repo = gh_data[4] or "#{user}.github.#{gh_data[3]}"
else
  user = localStorage.getItem location.href + '-user'
  if not user
    user = prompt "Your GitHub username for this blog:"
    localStorage.setItem location.href + '-user', user

  repo = localStorage.getItem location.href + '-repo'
  if not repo
    repo = prompt "The name of the repository in which this blog is hosted:"
    localStorage.setItem location.href + '-repo', repo

gh = new GitHub user
pass = prompt "Password for the user #{user}:"
if pass
  gh.password pass

gh.repo repo

Main = React.createClass
  getInitialState: ->
    editingDoc: 'home'

  componentWillMount: ->
    @db = Taffy.taffy()
    @db.settings
      template:
        parents: ['home']
        data: ''
        kind: 'article'
        title: ''
        text: ''
      onInsert: ->
        if not this._id
          this._id = "xyxxyxxx".replace /[xy]/g, (c) ->
            r = Math.random() * 16 | 0
            v = (if c is "x" then r else (r & 0x3 | 0x8))
            v.toString 16
      cacheSize: 0

    if not @db().count()
      @db.insert
        _id: 'home'
        parents: []
        kind: 'list'
        title: 'home'
        text: 'this is the text of the home page
               of this website about anything'

  setDocs: (docs) ->
    @db.merge(docs, '_id', true)
    @forceUpdate()

  setTemplate: (compiled) -> @setState template: compiled

  publish: ->
    if not @state.template
      return false

    processed = []
    console.log 'processing docs'

    # get the site params
    site =
      title: ''
      baseUrl: location.href.split('/').slice(0, -2).join('/') # because of the trailing /

    # add the pure docs
    for doc in @db().get()
      processed["_docs/#{doc._id}.json"] = JSON.stringify doc

    # recursively get the docs, render them and add
    goAfterTheChildrenOf = (parent, inheritedPathComponent='') =>
      # discover path
      if parent._id != 'home'
        pathComponent = inheritedPathComponent + parent.slug + '/'
      else
        pathComponent = ''

      # render and add
      html = render parent
      processed[pathComponent + 'index.html'] = html

      # go after its children
      q = @db({parents: {has: parent._id}})
      if not q.count()
        return false

      for doc in q.get()
        goAfterTheChildrenOf doc, pathComponent
        
    render = (doc) =>
      children = @db({parents: {has: doc._id}}).get()
      doc = CommonProcessor doc, children
      doc = Processors[doc.kind] doc
      rendered = @state.template
        doc: doc
        site: site
      return rendered

    goAfterTheChildrenOf @db({_id: 'home'}).first()
    console.log processed
    gh.deploy processed

  handleUpdateDoc: (docid, change) ->
    @db({_id: docid}).update(change)
    @forceUpdate()

  handleSelectDoc: (docid) ->
    @setState editingDoc: docid

  handleAddSon: (son) ->
    @db.insert(son)
    @forceUpdate()

  handleDeleteDoc: (docid) ->
    @db({_id: docid}).remove()
    @forceUpdate()

  handleMovingChilds: (childid, fromid, targetid) ->
    isAncestor = (base, potentialAncestor) =>
      doc = @db({_id: base}).first()
      if not doc.parents.length
        return false
      for parent in doc.parents
        if parent == potentialAncestor
          return true
        else
          return isAncestor parent, potentialAncestor

    if isAncestor targetid, childid
      return false
    else
      movedDoc = @db({_id: childid}).first()
      movedDoc.parents.splice movedDoc.parents.indexOf(fromid), 1
      movedDoc.parents.push targetid
      @db.merge(movedDoc, '_id', true)
      @forceUpdate()
      return true

  render: ->
    (div className: 'pure-g',
      (aside className: 'pure-u-1-5',
        (ul {},
          (Doc
            data: @db({_id: 'home'}).first()
            selected: true
            immediateParent: null
            onSelect: @handleSelectDoc
            onAddSon: @handleAddSon
            onMovedChild: @handleMovingChilds
            db: @db
          )
        )
      ),
      (main className: 'pure-u-4-5',
        (Menu
          showPublishButton: if @state.template then true else false
          onClickPublish: @publish
        ),
        (DocEditable
          data: @db({_id: @state.editingDoc}).first()
          onUpdateDocAttr: @handleUpdateDoc
          onDelete: @handleDeleteDoc
          db: @db
        )
      )
    )

Doc = React.createClass
  getInitialState: ->
    selected: @props.selected

  dragStart: (e) ->
    console.log 'started dragging ' + @props.data._id
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData 'docid', @props.data._id
    e.dataTransfer.setData 'fromid', @props.immediateParent

  drop: (e) ->
    e.preventDefault()
    e.stopPropagation()
    childid = e.dataTransfer.getData 'docid'
    fromid = e.dataTransfer.getData 'fromid'
    console.log childid + ' dropped here (at ' + @props.data._id + ') from ' + fromid
    movedOk = @props.onMovedChild childid, fromid, @props.data._id
    if movedOk
      @select()

  preventDefault: (e) -> e.preventDefault()

  select: ->
    @props.onSelect @props.data._id
    @setState selected: true

  clickRetract: ->
    @setState selected: false

  clickAdd: ->
    @select()
    @props.onAddSon {parents: [@props.data._id]}

  render: ->
    sons = @props.db(
      parents:
        has: @props.data._id
    ).get()

    if not sons.length
      sons = [{_id: ''}]

    if @props.data._id then (li {},
      (header
        onDragOver: @preventDefault
        onDrop: @drop
      ,
        (button
          className: 'pure-button retract'
          onClick: @clickRetract
        , '<'),
        (h4
          draggable: true
          onDragStart: @dragStart
          onClick: @select.bind(@, false)
          @props.data.title or @props.data._id),
        (button
          className: 'pure-button add'
          onClick: @clickAdd
        , '+')
      ),
      (ul {},
        @transferPropsTo (Doc
          data: son
          selected: false
          key: son._id
          immediateParent: @props.data._id
        ,
          son.title or son._id) for son in sons
      ) if @state.selected
    ) else (li {})

DocEditable = React.createClass
  handleChange: (attr, e) ->
    if attr == 'parents'
      value = (parent.trim() for parent in e.target.value.split(','))
    else
      value = e.target.value

    change = {}
    change[attr] = value
    @props.onUpdateDocAttr @props.data._id, change

  confirmDelete: ->
    if confirm "are you sure you want to delete 
        #{@props.data.title or @props.data._id}"
      @props.onDelete @props.data._id

  render: ->
    if not @props.data
      (article {})
    else
      (article className: 'editing',
        (h3 {}, "editing #{@props.data._id}"),
        (button
          className: 'pure-button del'
          onClick: @confirmDelete
        , 'x') if not @props.db({parents: {has: @props.data._id}}).count()
        (form
          className: 'pure-form pure-form-aligned'
          onSubmit: @handleSubmit
        ,
          (div className: 'pure-control-group',
            (label htmlFor: 'kind', 'kind: ')
            (select
              id: 'kind'
              onChange: @handleChange.bind @, 'kind'
              value: @props.data.kind
            ,
              (option
                value: kind
                key: kind
              , kind) for kind in Templates.names
            ),
          ),
          (div className: 'pure-control-group',
            (label htmlFor: 'title', 'title: ')
            (input
              id: 'title'
              className: 'pure-input-2-3'
              onChange: @handleChange.bind @, 'title'
              value: @props.data.title),
          ),
          (div className: 'pure-control-group',
            (label {}, 'parents: ')
            (input
              onChange: @handleChange.bind @, 'parents'
              value: @props.data.parents.join(', ')),
          ),
          (div className: 'pure-control-group',
            (label htmlFor: 'text', 'text: ')
            (textarea
              id: 'text'
              className: 'pure-input-2-3'
              onChange: @handleChange.bind @, 'text'
              value: @props.data.text),
          ),
          (div className: 'pure-control-group',
            (label htmlFor: 'data', 'data: ')
            (textarea
              wrap: 'off'
              id: 'data'
              className: 'pure-input-2-3'
              onChange: @handleChange.bind @, 'data'
              value: @props.data.data),
          ),
        )
      )

Menu = React.createClass
  handleClickPublish: (e) ->
    @props.onClickPublish()
    e.preventDefault()

  render: ->
    (header {},
      (button
        className: 'pure-button publish'
        onClick: @handleClickPublish
      , 'Publish!') if @props.showPublishButton
    )

# render component without any docs
MAIN = React.renderComponent Main(), document.body

# prepare docs to load
gh.listDocs (files) ->
  if Array.isArray files
    docAddresses = ('../' + f.path for f in files when f.type == 'file')
  else
    docAddresses = []
  # load docs
  TextLoad docAddresses, (docs...) ->
    MAIN.setDocs (JSON.parse doc for doc in docs)

    # load templates and precompile them
    TextLoad Templates.addresses, (templates...) ->
      dynamicTemplates = {}
      for templateString, i in templates
        dynamicTemplates[Templates.names[i]] = Handlebars.compile templateString

      Handlebars.registerHelper 'dynamicTemplate', (kind, context, opts) ->
        template = dynamicTemplates[kind]
        return new Handlebars.SafeString template context

      # register partials
      TextLoad Partials.addresses, (partials...) ->
        for partialString, i in partials
          Handlebars.registerPartial Partials.names[i], partialString

        # load the base template separatedly
        TextLoad BaseTemplate, (baseTemplateString) ->
          baseTemplate = Handlebars.compile baseTemplateString
          MAIN.setTemplate baseTemplate