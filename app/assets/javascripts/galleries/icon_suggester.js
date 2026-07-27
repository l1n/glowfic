/* exported IconSuggester */

/*
 * Suggests a keyword for an uploaded icon whose keyword looks auto-generated
 * (e.g. "IMG_2049", "tumblr_inline_abc123", "unnamed (3)"), by asking a small
 * vision-language model running in the browser what facial expression the
 * icon shows. The keyword doubles as the icon's alt/title text, so this helps
 * readers who rely on the mouseover to tell what an icon is meant to convey.
 *
 * - Privacy: the image never leaves the browser; there is no third-party AI
 *   API and no server-side inference.
 * - Opt-in: the model is a one-time download of roughly 400-500 MB, so the
 *   author is asked before the first one. Consent is remembered per browser.
 * - Suggestion only: the author clicks to accept; the field is never changed
 *   automatically.
 * - Inert unless WebGPU is available, and silently stops offering after any
 *   model load or inference failure.
 *
 * Model choice: Florence-2 was tried first but, being a captioner, it describes
 * emotive icons as e.g. "a yellow circle with three small eyes". An instruction
 * model can be asked about the expression directly; SmolVLM-500M is the
 * smallest that answered reliably (the 256M variant was close to random).
 */
const IconSuggester = (function() {
  // Pinned so a CDN-side major bump can't silently change the model API.
  const TRANSFORMERS_URL = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1';
  const MODEL_ID = 'HuggingFaceTB/SmolVLM-500M-Instruct';
  const PROMPT = 'In a few words, what is the facial expression? Reply with only the expression.';
  const CONSENT_KEY = 'iconSuggesterConsent';

  // Known auto-generated keyword stems, allowing trailing numbering like "(3)" or "_1".
  const JUNK_STEM = /^(img|image|photo|pic|picture|dsc|dscn|screen[\s_-]?shot|screenshot|unnamed|untitled|download|downloaded|default|avatar|icon|file|new|output|clipboard|paste|snap|capture)([\s_.-]*\(?\d+\)?)?$/i;

  let gpuPromise = null; // resolves to { f16 } or null when WebGPU is unusable
  let modelPromise = null;
  let disabled = false;
  let queue = Promise.resolve(); // one inference at a time keeps bulk uploads stable
  const downloaded = {}; // bytes per model file, for download progress

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

  // --- environment -------------------------------------------------------

  // navigator.gpu can exist while no adapter is available (common on Linux),
  // so only a successful adapter request counts as support.
  async function requestGpu() {
    if (!navigator.gpu) return null;
    try {
      const adapter = await navigator.gpu.requestAdapter();
      return adapter && { f16: adapter.features.has('shader-f16') };
    } catch {
      return null;
    }
  }

  function gpuSupport() {
    if (!gpuPromise) gpuPromise = requestGpu();
    return gpuPromise;
  }

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

  // --- model -------------------------------------------------------------

  function onDownloadProgress(progress) {
    if (progress.status !== 'progress') return;
    downloaded[progress.file] = progress.loaded;
    const megabytes = Object.values(downloaded).reduce(function(sum, bytes) { return sum + bytes; }, 0) / 1e6;
    $('.icon-suggestion.pending .icon-suggestion-text').text('downloading model… ' + Math.round(megabytes) + ' MB');
  }

  async function loadModel(gpu) {
    const lib = await import(TRANSFORMERS_URL);
    const [processor, model] = await Promise.all([
      lib.AutoProcessor.from_pretrained(MODEL_ID),
      lib.AutoModelForVision2Seq.from_pretrained(MODEL_ID, {
        device: 'webgpu',
        // fp16 embeddings halve the largest download but need shader-f16.
        dtype: { embed_tokens: gpu.f16 ? 'fp16' : 'fp32', vision_encoder: 'q4', decoder_model_merged: 'q4' },
        progress_callback: onDownloadProgress,
      }),
    ]);
    const messages = [{ role: 'user', content: [{ type: 'image' }, { type: 'text', text: PROMPT }] }];
    const prompt = processor.apply_chat_template(messages, { add_generation_prompt: true });
    return { RawImage: lib.RawImage, processor: processor, model: model, prompt: prompt };
  }

  async function describe(file, gpu) {
    if (!modelPromise) modelPromise = loadModel(gpu);
    const m = await modelPromise;
    const image = await m.RawImage.fromBlob(file);
    const inputs = await m.processor(m.prompt, [image], { do_image_splitting: false });
    const ids = await m.model.generate({ ...inputs, max_new_tokens: 16, do_sample: false });
    const answerIds = ids.slice(null, [inputs.input_ids.dims.at(-1), null]); // drop the echoed prompt
    return m.processor.batch_decode(answerIds, { skip_special_tokens: true })[0];
  }

  // " Frowning." -> "frowning"; "The facial expression is smiling." -> "smiling"
  function tidy(answer) {
    const phrase = String(answer || '').trim().split(/[.!?\n]/)[0];
    return phrase.replace(/^(the\s+)?(facial\s+)?expression\s+(shown\s+)?is\s+/i, '').trim().toLowerCase();
  }

  // --- UI ----------------------------------------------------------------

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

  function showOffer($chip, gpu) {
    const size = gpu.f16 ? 400 : 500;
    const $yes = $('<a href="#" class="icon-suggestion-use">Suggest a keyword from the image?</a>').on('click', function(e) {
      e.preventDefault();
      saveConsent();
      // Start every row that was waiting on this answer, not just this one.
      $('.icon-suggestion.offer').each(function() {
        const begin = $(this).data('start');
        if (begin) begin();
      });
    });
    $chip.addClass('offer').empty().append('✨ ', $yes,
      ' (one-time ~' + size + ' MB download, runs on your device) ', dismissLink($chip));
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

  async function suggest($chip, $input, file, gpu) {
    let suggestion = '';
    try {
      if (stillWanted($input)) suggestion = tidy(await describe(file, gpu));
    } catch {
      disabled = true; // load/inference failures recur, so stop offering
    }
    if (suggestion && stillWanted($input)) {
      showSuggestion($chip, $input, suggestion);
    } else {
      $chip.remove();
    }
  }

  function start($chip, $input, file, gpu) {
    showPending($chip);
    queue = queue.then(function() { return suggest($chip, $input, file, gpu); });
  }

  // --- entry point -------------------------------------------------------

  // Call after an upload. $input: the jQuery-wrapped keyword field; file: the uploaded File.
  async function suggestFor($input, file) {
    if (!file || !stillWanted($input)) return;
    const gpu = await gpuSupport();
    if (!gpu || !stillWanted($input)) return;

    const $chip = renderChip($input);
    const begin = function() { start($chip, $input, file, gpu); };
    if (hasConsent()) {
      begin();
    } else {
      $chip.data('start', begin);
      showOffer($chip, gpu);
    }
  }

  return { suggestFor: suggestFor, isLowInfoKeyword: isLowInfoKeyword };
}());
