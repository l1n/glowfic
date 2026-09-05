/* global createTagSelect, createSelect2 */

$(document).ready(function() {
  createSelect2('#user_per_page', {
    width: '70px',
    minimumResultsForSearch: 20,
  });

  createSelect2('#user_default_view', {
    width: '100px',
    minimumResultsForSearch: 20,
  });

  createSelect2('#user_default_character_split', {
    width: '250px',
    minimumResultsForSearch: 20,
  });

  createSelect2('#user_default_editor', {
    width: '100px',
    minimumResultsForSearch: 20,
  });

  createSelect2('#user_layout', {
    width: '150px',
    minimumResultsForSearch: 20,
  });

  createSelect2('#user_timezone', {width: '250px'});

  setupPreferredLanguages();

  createSelect2('#user_time_display', {
    width: '200px',
    minimumResultsForSearch: 20
  });
});

// An ordered multi-select. A <select multiple> submits its values in option order, not the
// order they were picked in, so each pick moves its <option> to the end of the list: the
// order shown, the order submitted and the order the user chose then all agree.
function setupPreferredLanguages() {
  const select = $('#user_preferred_languages');
  if (!select.length) { return; }

  // On load the server renders the saved languages first, in their saved order, so
  // move those options to the front before select2 draws them.
  select.find('option:selected').each(function() { $(this).detach().appendTo(select); });
  // ...and the unselected ones after, so the dropdown keeps its alphabetical order.
  select.find('option:not(:selected)').each(function() { $(this).detach().appendTo(select); });

  createSelect2('#user_preferred_languages', {
    width: '350px',
    placeholder: select.data('placeholder') || '',
    closeOnSelect: false,
  });

  select.on('select2:select', function(event) {
    const chosen = $(event.params.data.element);
    const lastSelected = select.find('option:selected').not(chosen).last();
    if (lastSelected.length) {
      chosen.detach().insertAfter(lastSelected);
    } else {
      chosen.detach().prependTo(select);
    }
    select.trigger('change.select2');
  });
}
