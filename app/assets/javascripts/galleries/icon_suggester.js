/* exported IconSuggester */

/*
 * In-browser icon description suggester (progressive enhancement).
 *
 * When an icon is uploaded and its keyword looks auto-generated / uninformative
 * (e.g. "IMG_2049", "tumblr_inline_abc123", "unnamed (3)"), and the browser can
 * run a vision model locally, we caption the image with a small VLM and offer
 * the author a suggested keyword. It is ALWAYS a suggestion the author accepts,
 * edits, or ignores -- we never overwrite the field automatically.
 *
 * Everything here is gated so it is completely inert when unsupported:
 *   - no WebGPU -> does nothing (today's behaviour, unchanged)
 *   - keyword already looks meaningful -> does nothing (we don't nag)
 *   - model fails to load / infer -> silently gives up
 *
 * The image never leaves the browser: no third-party AI API, no server-side
 * inference. The model weights are fetched lazily from a CDN only the first
 * time a suggestion is actually needed.
 *
 * Future work: a cheap face-detector + FER expression classifier could be
 * slotted into runModel() as a fast path for photo-real faces, falling back to
 * the VLM for illustrated / non-face icons.
 */
window.IconSuggester = (function() {
  // Pinned so a CDN-side major bump can't silently change the model API.
  const TRANSFORMERS_URL = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.5.1';
  const MODEL_ID = 'onnx-community/Florence-2-base-ft';
  const TASK = '<MORE_DETAILED_CAPTION>';
  const MAX_SUGGESTION_LENGTH = 80;

  // Known auto-generated / uninformative keyword stems, allowing trailing
  // numbering like "(3)" or "_1". Matched case-insensitively against the whole
  // trimmed keyword.
  const JUNK_STEM = /^(img|image|photo|pic|picture|dsc|dscn|screen[\s_-]?shot|screenshot|unnamed|untitled|download|downloaded|default|avatar|icon|file|new|output|clipboard|paste|snap|capture)([\s_.-]*\(?\d+\)?)?$/i;

  let modelPromise = null; // memoised across all suggestions on the page
  let queue = Promise.resolve(); // run inferences one at a time to avoid thrashing

  // --- support gate ------------------------------------------------------

  // WebGPU is required: on CPU/WASM a VLM is too slow for an interactive hint.
  function isSupported() {
    if (typeof navigator === 'undefined') return false;
    return typeof navigator.gpu !== 'undefined' && navigator.gpu !== null;
  }

  // --- garbage-keyword heuristic ----------------------------------------

  // Hash-like single token: no spaces, reasonably long, an alnum/-/_ token
  // containing at least one digit (so real words are never caught), and either
  // several digits or a long hex run.
  function looksLikeHash(kw) {
    if (/\s/.test(kw) || kw.length < 8) return false;
    if (!/^[a-z0-9_-]*\d[a-z0-9_-]*$/i.test(kw)) return false;
    return (kw.match(/\d/g) || []).length >= 3 || /[a-f0-9]{8,}/i.test(kw);
  }

  // Intentionally conservative: we would much rather miss a junk keyword than
  // nag an author who deliberately chose a short real one ("grin", "angry").
  function isLowInfoKeyword(raw) {
    const kw = (raw || '').trim();
    if (!kw) return true;
    if (/^[\d\s_.()-]+$/.test(kw)) return true; // pure numbering: "2", "(4)", "1-2"
    if (JUNK_STEM.test(kw)) return true;
    if (/^tumblr[_\d]/i.test(kw)) return true; // "tumblr_inline_..." exports
    return looksLikeHash(kw);
  }

  // --- model loading + inference ----------------------------------------

  function loadModel() {
    return import(TRANSFORMERS_URL).then(function(t) {
      return Promise.all([
        t.Florence2ForConditionalGeneration.from_pretrained(MODEL_ID, { dtype: 'fp32', device: 'webgpu' }),
        t.AutoProcessor.from_pretrained(MODEL_ID),
        t.AutoTokenizer.from_pretrained(MODEL_ID)
      ]).then(function(parts) {
        return { lib: t, model: parts[0], processor: parts[1], tokenizer: parts[2] };
      });
    });
  }

  function getModel() {
    if (!modelPromise) modelPromise = loadModel();
    return modelPromise;
  }

  function generateCaption(m, image) {
    const prompts = m.processor.construct_prompts(TASK);
    const textInputs = m.tokenizer(prompts);
    return m.processor(image).then(function(visionInputs) {
      const inputs = Object.assign({ max_new_tokens: 100 }, textInputs, visionInputs);
      return m.model.generate(inputs).then(function(ids) {
        const decoded = m.tokenizer.batch_decode(ids, { skip_special_tokens: false })[0];
        const result = m.processor.post_process_generation(decoded, TASK, image.size);
        return result[TASK];
      });
    });
  }

  function runModel(blob) {
    return getModel().then(function(m) {
      return m.lib.RawImage.fromBlob(blob).then(function(image) {
        return generateCaption(m, image);
      });
    });
  }

  // Turn a model caption into a short, keyword-friendly phrase.
  function tidy(caption) {
    if (!caption) return '';
    const text = String(caption).trim().replace(/\s+/g, ' ');
    let phrase = text.split(/(?<=[.!?])\s/)[0] || text; // first sentence only
    phrase = phrase.replace(/^(the\s+image\s+(shows|depicts|is\s+of)|this\s+is|an?\s+image\s+of)\s+/i, '');
    phrase = phrase.replace(/[.\s]+$/, '');
    if (phrase.length > MAX_SUGGESTION_LENGTH) {
      phrase = phrase.slice(0, MAX_SUGGESTION_LENGTH).replace(/\s+\S*$/, '') + '…';
    }
    return phrase.charAt(0).toLowerCase() + phrase.slice(1);
  }

  // --- UI ----------------------------------------------------------------

  function renderPending($input) {
    const $chip = $('<div class="icon-suggestion pending" aria-live="polite">' +
      '✨ <span class="icon-suggestion-text">describing…</span></div>');
    $input.after($chip);
    return $chip;
  }

  function renderSuggestion($chip, $input, suggestion) {
    $chip.removeClass('pending').empty();
    const $use = $('<a href="#" class="icon-suggestion-use"></a>').text('“' + suggestion + '”');
    const $dismiss = $('<a href="#" class="icon-suggestion-dismiss" title="Dismiss">×</a>');
    $chip.append($('<span class="icon-suggestion-label">Suggested: </span>')).append($use).append(' ').append($dismiss);

    $use.on('click', function(e) {
      e.preventDefault();
      $input.val(suggestion).trigger('change').focus();
      $chip.remove();
    });
    $dismiss.on('click', function(e) {
      e.preventDefault();
      $chip.remove();
    });
  }

  // --- entry point -------------------------------------------------------

  function shouldSuggest($input, blob) {
    if (!$input || !$input.length || !blob) return false;
    if (!isSupported()) return false;
    return isLowInfoKeyword($input.val());
  }

  // $input: jQuery-wrapped keyword <input>. blob: the uploaded File/Blob.
  function suggestFor($input, blob) {
    try {
      if (!shouldSuggest($input, blob)) return;

      $input.nextAll('.icon-suggestion').remove(); // avoid stacking chips
      const $chip = renderPending($input);

      // Serialise inferences: one VLM run at a time keeps a bulk upload stable.
      queue = queue.then(function() {
        // If the author has meanwhile typed a real keyword, don't bother.
        if (!isLowInfoKeyword($input.val())) {
          $chip.remove();
          return null;
        }
        return runModel(blob).then(function(caption) {
          const suggestion = tidy(caption);
          if (suggestion && isLowInfoKeyword($input.val())) {
            renderSuggestion($chip, $input, suggestion);
          } else {
            $chip.remove();
          }
        });
      }).catch(function() {
        // Any failure (unsupported op, load error, OOM) -> silently degrade.
        $chip.remove();
      });
    } catch {
      // Never let a suggestion attempt break the upload flow.
    }
  }

  return {
    suggestFor: suggestFor,
    isLowInfoKeyword: isLowInfoKeyword,
    isSupported: isSupported
  };
}());
