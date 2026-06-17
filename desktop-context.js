/**
 * Stello desktop-context bridge — localhost only.
 *
 * Calls the com.stello.context daemon on 127.0.0.1:8766 for Mac-context
 * related items. No-ops in production (returns null).
 */
(function () {
  'use strict';

  var DAEMON_ORIGIN = 'http://127.0.0.1:8766';

  function isLocalhost() {
    var host = window.location.hostname;
    return host === 'localhost' || host === '127.0.0.1';
  }

  /**
   * @param {number} [k=10] Max related items to request.
   * @returns {Promise<object|null>} Parsed /related JSON, or null when gated/offline.
   */
  async function fetchDesktopRelated(k) {
    if (!isLocalhost()) return null;
    var limit = k == null ? 10 : k;
    try {
      var url =
        DAEMON_ORIGIN +
        '/related?k=' +
        encodeURIComponent(String(limit));
      var res = await fetch(url);
      if (!res.ok) return null;
      return await res.json();
    } catch (_err) {
      return null;
    }
  }

  window.stelloDesktop = {
    fetchRelated: fetchDesktopRelated,
  };
})();
