//= require galleries/icon_suggester_backends
/* global IconSuggesterBackends */
/* exported IconSuggester */

/*
 * Suggests a keyword for an uploaded icon whose keyword looks auto-generated
 * (e.g. "IMG_2049", "tumblr_inline_abc123", "unnamed (3)"), by asking an
 * on-device vision-language model (see icon_suggester_backends.js) what facial
 * expression the icon shows. The keyword doubles as the icon's alt/title text,
 * so this helps readers who rely on the mouseover to tell what an icon is
 * meant to convey.
 *
 * Suggestions are only ever offered; the author clicks to accept one. When a
 * model download is needed the author is asked first, with the download cost
 * spelled out. The suggester is inert when no backend can run, and stops
 * offering after any model load or inference failure.
 */
const IconSuggester = (function() {
  const CONSENT_KEY = 'iconSuggesterConsent';

  // Known auto-generated keyword stems, allowing trailing numbering like "(3)" or "_1".
  const JUNK_STEM = /^(img|image|photo|pic|picture|dsc|dscn|screen[\s_-]?shot|screenshot|unnamed|untitled|download|downloaded|default|avatar|icon|file|new|output|clipboard|paste|snap|capture)([\s_.-]*\(?\d+\)?)?$/i;

  let backendPromise = null; // resolves to the chosen backend, or null if none
  let started = false; // a model has been asked to load on this page
  let disabled = false;
  let queue = Promise.resolve(); // one inference at a time keeps bulk uploads stable

  // --- keyword heuristic -------------------------------------------------

  // Hash-like single token: an alnum/-/_ token containing a digit (so real
  // words are never caught), with several digits or a long hex run.
  function looksLikeHash(kw) {
    if (/\s/.test(kw) || kw.length < 8) return false;
    if (!/^[a-z0-9_-]*\d[a-z0-9_-]*$/i.test(kw)) return false;
    return (kw.match(/\d/g) || []).length >= 3 || /[a-f0-9]{8,}/i.test(kw);
  }

  // Deliberately conservative: better to miss a junk keyword than to nag an
  // author who chose a short real one ("grin", "angry").
  function isLowInfoKeyword(raw) {
    const kw = (raw || '').trim();
    if (!kw) return true;
    if (/^[\d\s_.()-]+$/.test(kw)) return true; // pure numbering: "2", "(4)", "1-2"
    if (JUNK_STEM.test(kw)) return true;
    if (/^tumblr[_\d]/i.test(kw)) return true; // "tumblr_inline_..." exports
    return looksLikeHash(kw);
  }

  // " Frowning." -> "frowning"; "The facial expression is smiling." -> "smiling"
  function tidy(answer) {
    const phrase = String(answer || '').trim().split(/[.!?\n]/)[0];
    return phrase.replace(/^(the\s+)?(facial\s+)?expression\s+(shown\s+)?is\s+/i, '')
      .replace(/^["'“”]+|["'“”]+$/g, '').trim().toLowerCase();
  }

  // --- consent -----------------------------------------------------------

  function hasConsent() {
    try {
      return window.localStorage.getItem(CONSENT_KEY) === 'yes';
    } catch {
      return false;
    }
  }

  function saveConsent() {
    try {
      window.localStorage.setItem(CONSENT_KEY, 'yes');
    } catch {
      // Private browsing etc.: consent then lasts only for this page.
    }
  }

  function canStartNow(backend) {
    return started || backend.downloaded || (backend.rememberConsent && hasConsent());
  }

  // --- UI ----------------------------------------------------------------

  function showProgress(text) {
    $('.icon-suggestion.pending .icon-suggestion-text').text(text);
  }

  function stillWanted($input) {
    return !disabled && document.body.contains($input[0]) && isLowInfoKeyword($input.val());
  }

  function renderChip($input) {
    $input.nextAll('.icon-suggestion').remove();
    const $chip = $('<div class="icon-suggestion" aria-live="polite"></div>');
    $input.after($chip);
    return $chip;
  }

  function dismissLink($chip) {
    return $('<a href="#" class="icon-suggestion-dismiss" title="Dismiss">×</a>').on('click', function(e) {
      e.preventDefault();
      $chip.remove();
    });
  }

  function showOffer($chip, backend) {
    const $yes = $('<a href="#" class="icon-suggestion-use">Suggest a keyword from the image?</a>').on('click', function(e) {
      e.preventDefault();
      saveConsent();
      started = true;
      // Inside the click, where Chrome allows a model download to start.
      backend.prepare(showProgress).catch(function() { disabled = true; });
      // Start every row that was waiting on this answer, not just this one.
      $('.icon-suggestion.offer').each(function() {
        const begin = $(this).data('start');
        if (begin) begin();
      });
    });
    $chip.addClass('offer').empty().append('✨ ', $yes, ' ' + backend.offer + ' ', dismissLink($chip));
  }

  function showPending($chip) {
    $chip.removeClass('offer').addClass('pending').empty().append('✨ ', $('<span class="icon-suggestion-text">describing…</span>'));
  }

  function showSuggestion($chip, $input, suggestion) {
    const $use = $('<a href="#" class="icon-suggestion-use"></a>').text('“' + suggestion + '”').on('click', function(e) {
      e.preventDefault();
      $input.val(suggestion).trigger('change').focus();
      $chip.remove();
    });
    $chip.removeClass('pending').empty().append('Suggested: ', $use, ' ', dismissLink($chip));
  }

  async function suggest($chip, $input, file, backend) {
    let suggestion = '';
    try {
      if (stillWanted($input)) suggestion = tidy(await backend.describe(file, showProgress));
    } catch {
      disabled = true; // load/inference failures recur, so stop offering
    }
    if (suggestion && stillWanted($input)) {
      showSuggestion($chip, $input, suggestion);
    } else {
      $chip.remove();
    }
  }

  function start($chip, $input, file, backend) {
    started = true;
    showPending($chip);
    queue = queue.then(function() { return suggest($chip, $input, file, backend); });
  }

  function getBackend() {
    if (!backendPromise) backendPromise = IconSuggesterBackends.choose();
    return backendPromise;
  }

  // --- entry point -------------------------------------------------------

  // Call after an upload. $input: the jQuery-wrapped keyword field; file: the uploaded File.
  async function suggestFor($input, file) {
    if (!file || !stillWanted($input)) return;
    const backend = await getBackend();
    if (!backend || !stillWanted($input)) return;

    const $chip = renderChip($input);
    const begin = function() { start($chip, $input, file, backend); };
    if (canStartNow(backend)) {
      begin();
    } else {
      $chip.data('start', begin);
      showOffer($chip, backend);
    }
  }

  return { suggestFor: suggestFor, isLowInfoKeyword: isLowInfoKeyword };
}());
