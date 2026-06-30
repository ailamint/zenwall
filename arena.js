/*
 * are.na source — fetches a public channel's image blocks client-side.
 *
 * The are.na API and its image CDN both send `Access-Control-Allow-Origin: *`,
 * so we can read channels and draw their images onto a canvas that stays
 * "clean" (exportable) as long as the <img> uses crossOrigin = 'anonymous'.
 *
 * Attaches a single global `Arena`.
 */
(function (global) {
  'use strict';

  var API = 'https://api.are.na/v3';
  var PER_PAGE = 100;

  // Accept a full are.na URL, an API URL, or a bare slug.
  function slugFromInput(input) {
    var s = (input || '').trim();
    if (!s) return '';
    var m = s.match(/\/channels\/([^/?#]+)/);
    if (m) return m[1];
    m = s.match(/are\.na\/[^/]+\/([^/?#]+)/);
    if (m) return m[1];
    // Bare slug or "username/channel" — take the last path segment.
    return s.replace(/\/+$/, '').split('/').pop();
  }

  // Prefer the largest pre-sized variant available; fall back to original.
  function bestSrc(image) {
    if (!image) return null;
    if (image.large && image.large.src) return image.large.src;
    if (image.original && image.original.src) return image.original.src;
    if (image.display && image.display.src) return image.display.src;
    if (image.medium && image.medium.src) return image.medium.src;
    return image.src || null;
  }

  /*
   * fetchChannel(input, opts)
   *   opts.limit    : max image URLs to collect (default 200)
   *   opts.onPage   : (collectedCount, totalGuess) => void  progress callback
   * returns Promise<{ slug, title, urls: string[] }>
   */
  function fetchChannel(input, opts) {
    opts = opts || {};
    var limit = opts.limit || 200;
    var onPage = opts.onPage || function () {};
    var slug = slugFromInput(input);
    if (!slug) return Promise.reject(new Error('Could not read a channel from that input.'));

    var urls = [];
    var title = slug;

    function page(p) {
      var url = API + '/channels/' + encodeURIComponent(slug) +
        '/contents?per=' + PER_PAGE + '&page=' + p;
      return fetch(url).then(function (res) {
        if (!res.ok) {
          if (res.status === 404) throw new Error('Channel "' + slug + '" not found (is it public?).');
          throw new Error('are.na returned ' + res.status + '.');
        }
        return res.json();
      }).then(function (data) {
        if (data.title) title = data.title;
        var blocks = data.contents || data.data || [];
        for (var i = 0; i < blocks.length; i++) {
          if (urls.length >= limit) break;
          var src = bestSrc(blocks[i].image);
          if (src) urls.push(src);
        }
        onPage(urls.length, data.length || urls.length);
        if (blocks.length < PER_PAGE || urls.length >= limit) {
          return { slug: slug, title: title, urls: urls };
        }
        return page(p + 1);
      });
    }

    return page(1).then(function (result) {
      if (!result.urls.length) throw new Error('That channel has no images.');
      return result;
    });
  }

  global.Arena = { fetchChannel: fetchChannel, slugFromInput: slugFromInput };
})(window);
