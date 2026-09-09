/* global createTagSelect */
$(document).ready(function() {
  // Only settings have parent settings, but every tag type has translations, so this
  // file is loaded for all of them and the select is set up only when it's on the page.
  const parentSettings = $("#tag_parent_setting_ids");
  if (parentSettings.length) {
    createTagSelect("Setting", "parent_setting", "tag", {tag_id: parentSettings.data('tag-id')});
  }

  setupTagTranslations();
});

// Adds a blank translation row by cloning the <template> the server rendered, renumbering
// its field names so Rails treats it as a new nested record.
function setupTagTranslations() {
  const container = $("#tag-translations");
  const template = document.getElementById("tag-translation-template");
  if (!container.length || !template) { return; }

  $("#add-tag-translation").click(function() {
    const index = container.data('next-index');
    container.data('next-index', index + 1);

    const markup = template.innerHTML.replace(/NEW_RECORD/g, index);
    const row = $(markup).appendTo(container);
    row.find('.tag-translation-locale').first().focus();
  });

  // Keep the name/description fields tagged with the language that's selected for them,
  // so the browser spellchecks and renders each row in the right language as you type.
  container.on('change', '.tag-translation-locale', function() {
    const row = $(this).closest('.tag-translation');
    const locale = $(this).val();
    row.find('input[type=text], textarea').attr('lang', locale || null);
  });
}
