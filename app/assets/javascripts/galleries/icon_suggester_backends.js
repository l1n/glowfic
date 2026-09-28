/* exported IconSuggesterBackends */

/*
 * On-device vision models for icon_suggester.js. Both backends run entirely on
 * the author's device; the image never leaves the browser.
 *
 * - Chrome's built-in model (Prompt API): preferred. Nothing for us to ship,
 *   and when the model is already on the device no download is needed.
 * - SmolVLM-500M via transformers.js + WebGPU: fallback for browsers without
 *   built-in AI; a ~400-500 MB download needing ~1.5 GB of memory.
 *
 * Why SmolVLM-500M: Florence-2 is a captioner and described emotive icons as
 * e.g. "a yellow circle with three small eyes"; SmolVLM-256M answered close to
 * randomly. SmolVLM-500M named a plausible expression for every test image.
 *
 * choose() resolves to a backend, or null when neither can run:
 *   downloaded       model already on the device: fine to start without asking
 *   rememberConsent  a remembered "yes" is enough to start (Chrome instead needs
 *                    a fresh click whenever it has to download its model)
 *   offer            download warning to show before asking
 *   prepare(onProgress)        start loading; idempotent. Call it inside the
 *                              click handler, where Chrome allows a download.
 *   describe(file, onProgress) the model's answer for one image
 */
const IconSuggesterBackends = (function() {
  const PROMPT = 'In a few words, what is the facial expression? Reply with only the expression.';
  const SYSTEM_PROMPT = 'You suggest keywords for character icons on a collaborative fiction site. ' +
    'Reply with only the facial expression or mood shown, in one to four lowercase words.';
  const LANGUAGE_MODEL_OPTIONS = {
    expectedInputs: [{ type: 'text', languages: ['en'] }, { type: 'image' }],
    expectedOutputs: [{ type: 'text', languages: ['en'] }],
  };

  // Pinned so a CDN-side major bump can't silently change the model API.
  const TRANSFORMERS_URL = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1';
  const FALLBACK_MODEL_ID = 'HuggingFaceTB/SmolVLM-500M-Instruct';

  function makeBackend(spec) {
    let model = null;
    function prepare(onProgress) {
      if (!model) model = spec.load(onProgress);
      return model;
    }
    return {
      downloaded: spec.downloaded,
      rememberConsent: spec.rememberConsent,
      offer: spec.offer,
      prepare: prepare,
      describe: async function(file, onProgress) { return spec.run(await prepare(onProgress), file); },
    };
  }

  // --- Chrome's built-in model -------------------------------------------

  function createChromeSession(onProgress) {
    return LanguageModel.create({
      ...LANGUAGE_MODEL_OPTIONS,
      initialPrompts: [{ role: 'system', content: SYSTEM_PROMPT }],
      monitor: function(m) {
        m.addEventListener('downloadprogress', function(e) {
          onProgress('Chrome is downloading its AI model… ' + Math.round(e.loaded * 100) + '%');
        });
      },
    });
  }

  // Each icon gets a clone of the base session, so context doesn't pile up.
  async function promptChrome(baseSession, file) {
    const session = await baseSession.clone();
    try {
      return await session.prompt([{ role: 'user', content: [{ type: 'text', value: PROMPT }, { type: 'image', value: file }] }]);
    } finally {
      session.destroy();
    }
  }

  async function chrome() {
    if (typeof LanguageModel === 'undefined') return null;
    try {
      const availability = await LanguageModel.availability(LANGUAGE_MODEL_OPTIONS);
      if (availability === 'unavailable') return null;
      return makeBackend({
        downloaded: availability === 'available',
        rememberConsent: false,
        offer: '(Chrome downloads its built-in AI model once; it runs on your device)',
        load: createChromeSession,
        run: promptChrome,
      });
    } catch {
      return null;
    }
  }

  // --- SmolVLM fallback --------------------------------------------------

  async function loadSmolVLM(f16, onProgress) {
    const downloaded = {}; // bytes per model file
    const lib = await import(TRANSFORMERS_URL);
    const [processor, model] = await Promise.all([
      lib.AutoProcessor.from_pretrained(FALLBACK_MODEL_ID),
      lib.AutoModelForVision2Seq.from_pretrained(FALLBACK_MODEL_ID, {
        device: 'webgpu',
        // fp16 embeddings halve the largest download but need shader-f16.
        dtype: { embed_tokens: f16 ? 'fp16' : 'fp32', vision_encoder: 'q4', decoder_model_merged: 'q4' },
        progress_callback: function(progress) {
          if (progress.status !== 'progress') return;
          downloaded[progress.file] = progress.loaded;
          const megabytes = Object.values(downloaded).reduce(function(sum, bytes) { return sum + bytes; }, 0) / 1e6;
          onProgress('downloading model… ' + Math.round(megabytes) + ' MB');
        },
      }),
    ]);
    const messages = [{ role: 'user', content: [{ type: 'image' }, { type: 'text', text: PROMPT }] }];
    const prompt = processor.apply_chat_template(messages, { add_generation_prompt: true });
    return { RawImage: lib.RawImage, processor: processor, model: model, prompt: prompt };
  }

  async function promptSmolVLM(m, file) {
    const image = await m.RawImage.fromBlob(file);
    const inputs = await m.processor(m.prompt, [image], { do_image_splitting: false });
    const ids = await m.model.generate({ ...inputs, max_new_tokens: 16, do_sample: false });
    const answerIds = ids.slice(null, [inputs.input_ids.dims.at(-1), null]); // drop the echoed prompt
    return m.processor.batch_decode(answerIds, { skip_special_tokens: true })[0];
  }

  // navigator.gpu can exist while no adapter is available (common on Linux),
  // so only a successful adapter request counts as support.
  async function smolVLM() {
    if (!navigator.gpu) return null;
    try {
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) return null;
      const f16 = adapter.features.has('shader-f16');
      return makeBackend({
        downloaded: false,
        rememberConsent: true,
        offer: '(heads up: this browser has no built-in AI, so this downloads a ~' + (f16 ? 400 : 500) +
          ' MB model once and needs ~1.5 GB of memory; it runs on your device)',
        load: function(onProgress) { return loadSmolVLM(f16, onProgress); },
        run: promptSmolVLM,
      });
    } catch {
      return null;
    }
  }

  async function choose() {
    return (await chrome()) || smolVLM();
  }

  return { choose: choose };
}());
