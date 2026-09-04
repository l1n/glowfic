/* global gon, tinyMCE */
/* exported setupEditorHelpBox, setupLanguageBar, toggleEditor, setupTinyMCE */

let tinyMCEInit = false;

function tinyMCEConfig(selector) {
  const height = ($(selector).height() || 150) + 15;
  return {
    // integration configs
    selector: selector,
    plugins: ["wordcount", "image", "link", "autoresize"],
    cache_suffix: '?v=7.8.0-2025-05-11',
    license_key: 'gpl',
    // interface configs
    menubar: false, // disable "File", "Edit", etc
    contextmenu: false,
    min_height: height,
    // - toolbar
    toolbar_sticky: true,
    toolbar: ["bold italic underline strikethrough forecolor | link image | blockquote hr bullist numlist | language | undo redo"],
    // - statusbar
    statusbar: true,
    branding: false,
    elementpath: false,
    resize: true,
    // editor content behavior
    body_class: gon.editor_class,
    custom_undo_redo_levels: 10,
    content_css: gon.tinymce_css_path,
    browser_spellcheck: true,
    document_base_url: gon.base_url,
    relative_urls: false,
    remove_script_host: true,
    text_patterns: false, // disable markdown-like autoformatting from TinyMCE 6 (for now)
    // - language: the toolbar's language menu wraps the selection in <span lang="…">
    content_langs: contentLanguages(),
    // plugin configs
    // - autoresize
    autoresize_bottom_margin: 5,
  };
}

// The languages offered by the editor's language controls, with the writer's own
// language first: it's the one they reach for most, and the rest stay alphabetical.
function contentLanguages() {
  const languages = (gon.content_languages || []).slice();
  const preferred = gon.writing_language;
  return languages.sort(function(a, b) {
    if (a.code === b.code) { return 0; }
    if (a.code === preferred) { return -1; }
    if (b.code === preferred) { return 1; }
    return 0;
  });
}

function setupEditorHelpBox() {
  const editorHelp = $("#editor-help-box");
  const defaultHelpWidth = 500;
  const defaultHelpHeight = 700;
  editorHelp.dialog({
    autoOpen: false,
    title: 'Editor Help',
    width: defaultHelpWidth,
    height: defaultHelpHeight
  });

  $('#editor-help').click(function() {
    if (editorHelp.dialog('isOpen')) {
      editorHelp.dialog('close');
    } else {
      const width = Math.min($(window).width()-20, defaultHelpWidth);
      const height = Math.min($(window).height()-20, defaultHelpHeight);
      editorHelp.dialog('option', {width: width, height: height}).dialog('open');
      editorHelp.dialog('open');
    }
  });
}

function toggleEditor(button, editorModeSelectorID, mceEditorIDs) {
  /* Toggle the editor mode depending on which editor button was clicked. */
  const clickedEditorMode = button.id;

  // Unselect all editor modes that were not the one clicked
  for (const editorMode of ['html', 'md', 'rtf']) {
    if (editorMode === clickedEditorMode) {
      continue;
    }

    $("#" + editorMode).removeClass('selected');
  }

  // Select the clicked editor mode and update the hidden form field with the appropriate value
  $(button).addClass('selected');
  $("#" + editorModeSelectorID).val(clickedEditorMode);
  updateLanguageBar();

  // Enable or disable the tinyMCE editor depending on the editor mode selected
  if (clickedEditorMode === 'rtf') {
    if (tinyMCEInit) {
      for (const mceEditorID of mceEditorIDs) {
        tinyMCE.execCommand('mceAddEditor', true, { id: mceEditorID, options: tinyMCEConfig('#' + mceEditorID) });
      }
    } else {
      setupTinyMCE();
    }
  } else {
    for (const mceEditorID of mceEditorIDs) {
      tinyMCE.execCommand('mceRemoveEditor', false, mceEditorID);
    }
  }
}

function setupTinyMCE() {
  const selector = 'textarea.tinymce';
  if (typeof tinyMCE === 'undefined') {
    setTimeout(setupTinyMCE, 50);
  } else {
    tinyMCE.init(tinyMCEConfig(selector));
    tinyMCEInit = true;
  }
}

// The HTML and Markdown editors are plain textareas, so they don't get TinyMCE's language
// menu; this is the equivalent for them. It wraps the selected text in <span lang="…">,
// or drops an empty one at the caret to type inside when nothing is selected.
function setupLanguageBar(textareaSelector) {
  const bar = $('#editor-language-bar');
  if (!bar.length) { return; }

  const select = $('#editor-language');
  for (const language of contentLanguages()) {
    select.append($('<option>', { value: language.code, text: language.title }));
  }
  select.val(gon.writing_language);

  $('#editor-language-wrap').click(function() {
    const textarea = $(textareaSelector).filter(':visible').get(0);
    wrapSelectionInLanguage(textarea, select.val());
  });

  updateLanguageBar();
}

function wrapSelectionInLanguage(textarea, locale) {
  if (!textarea || !locale) { return; }

  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const opening = '<span lang="' + locale + '">';
  const closing = '</span>';
  const value = textarea.value;

  textarea.value = value.slice(0, start) + opening + value.slice(start, end) + closing + value.slice(end);

  // With text selected the caret goes after the wrapped passage; with nothing selected it
  // goes inside the new span, which is where the writer is about to type.
  const caret = (start === end) ? start + opening.length : end + opening.length + closing.length;
  textarea.focus();
  textarea.setSelectionRange(caret, caret);
}

// TinyMCE has its own language menu, so the bar is only for the other two editors.
function updateLanguageBar() {
  $('#editor-language-bar').toggleClass('hidden', $('#rtf').hasClass('selected'));
}
