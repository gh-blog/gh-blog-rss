fs = require 'fs'
Path = require 'path'
through2 = require 'through2'
URL = require 'url'
File = require 'vinyl'
Feed = require 'feed'
_ = require 'lodash'
cheerio = require 'cheerio'

# requires = ['html', 'info', 'metadata?', 'url']
# optional = ['categories']

externalRegExp = new RegExp '^((ftp|http)s?:)?//', 'i'

module.exports = (options = { }) ->
    options = _.defaults options, {
        filename: 'rss.xml'
        full: yes
        format: 'atom-1.0'
        resolve: '.'
    }

    { filename, blog } = options

    if not filename
        throw new Error 'No path specified for RSS file'

    if typeof blog.link isnt 'string'
        throw new TypeError 'RSS feeds do not support relative URLs, please
        specify a host to resolve feed URLs against'

    resolve = (url) ->
        URL.resolve blog.link, (Path.join options.resolve, url || '')

    isRelative = (url) ->
        Boolean not url.match externalRegExp

    config =
        _.chain(blog)
        # .pick ['title', 'description', 'link'] #@TODO:
        .defaults { author: blog.authors[0] }
        .value()

    # @TODO: resolve Blog main image if exists

    feed = new Feed config
    items = []

    processFile = (file, enc, done) ->
        if file.isPost
            item = {  }
            item.author = file.author
            item.title = file.title

            item.date = file.created?.date || new Date
            item.contributor = file.contributors || []
            # @TODO: url plugin
            item.link = resolve file.relative
            # @TODO: pick a nice image and resovle it
            item.image = resolve file.images[0]

            if options.full
                $ = cheerio.load String file.contents
                $('img').each (i, el) ->
                    $el = $(el)
                    url = $el.attr 'src'
                    $el.attr 'src', resolve url if isRelative url

                $('h1:first-of-type').remove()
                item.description = $.html()
            else
                item.description = file.excerpt || ''

            # @TODO: should we check for duplicates?
            for contributor in item.contributor
                feed.addContributor contributor

            # @TODO: resolve all relative links in a[href] and img[src]...

            items.push item

        done null, file

    through2.obj processFile, (done) ->

        for item in _.sortBy(items, 'date').reverse()
            feed.addItem item

        xml = feed.render options.format
        rssFile = new File path: filename
        rssFile.contents = new Buffer xml

        @push rssFile
        done()