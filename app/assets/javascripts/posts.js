$(document).ready(function() {
  $("#post_board_id").chosen({
    width: '200px',
    disable_search_threshold: 20,
  });

  $("#post_privacy").chosen({
    width: '200px',
    disable_search_threshold: 20,
  });

  $("#post_post_viewer_ids").chosen({
    width: '200px',
    disable_search_threshold: 20,
    placeholder_text_multiple: 'Choose user(s) to view this post'
  });

  $("#active_character").chosen({
    disable_search_threshold: 10,
    width: '100%',
  });

  $(".post-screenname").each(function (index) {
    if($(this).height() > 20) {
      $(this).css('font-size', "14px");
      if($(this).height() > 20 ) { $(this).css('font-size', "12px"); };
    }
  });

  // Hack to deal with Firefox's "helpful" caching of form values on soft refresh
  var nameInSelect = $("#active_character").children("optgroup").children(':selected').text().split(" | ")[0];
  var nameInUI = $("#post-editor .post-character").text();
  if (nameInUI != nameInSelect) {
    var characterId = $("#reply_character_id").val();
    getAndSetCharacterData(characterId);
  };

  $("#post-menu").click(function() { 
    $(this).toggleClass('selected');
    $("#post-menu-box").toggle();
  });

  $('.view-button').click(function() {
    if(this.id == 'rtf') {
      $("#html").removeClass('selected');
      $(this).addClass('selected');
      tinyMCE.execCommand('mceAddEditor', true, 'post_content');
      tinyMCE.execCommand('mceAddEditor', true, 'reply_content');
    } else {
      $("#rtf").removeClass('selected');
      $(this).addClass('selected');
      tinyMCE.execCommand('mceRemoveEditor', false, 'post_content');
      tinyMCE.execCommand('mceRemoveEditor', false, 'reply_content');
    };
  });

  $("#post_privacy").change(function() {
    if($(this).val() == 2) { // TODO don't hardcode, should be PRIVACY_ACCESS
      $("#access_list").show();
    } else {
      $("#access_list").hide();
    }
  });

  $(".post-expander").click(function() {
    $(".post-expander .info").remove();
    $(".post-expander .hidden").show();
  });

  $("#submit_button").click(function() {
    $("#preview_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    $("#draft_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    return true;
  });

  $("#preview_button").click(function() {
    $("#submit_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    $("#draft_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    return true;
  });

  $("#draft_button").click(function() {
    $("#submit_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    $("#preview_button").removeAttr('data-disable-with').attr('disabled', 'disabled');
    return true;
  });

  if($(".gallery-icon").length > 1) {
    bindIcon();
    bindGallery();
  }

  $("#swap-icon").click(function () {
    $('#character-selector').toggle();
    $('html, body').scrollTop($("#post-editor").offset().top);
  });

  $("#active_character_chosen").click(function () {
    $('html, body').scrollTop($("#post-editor").offset().top);
  });

  $("#active_character").change(function() { 
    // Set the ID
    var id = $(this).val();
    $("#reply_character_id").val(id);
    getAndSetCharacterData(id);
  });

  // Hides selectors when you hit the escape key
  $(document).bind("keydown", function(e){ 
    e = e || window.event;
    var charCode = e.which || e.keyCode;
    if(charCode == 27) {
      $('#icon-overlay').hide();
      $('#gallery').hide();
      $('#character-selector').hide();
      $('#post-menu-box').hide();
      $('#post-menu').removeClass('selected');
    }
  });

  // Hides selectors when you click outside them
  $(document).click(function(e) {
    var target = e.target;

    if (!$(target).is('#current-icon-holder') && 
      !$(target).parents().is('#current-icon-holder') &&
      !$(target).is('#gallery') && 
      !$(target).parents().is('#gallery')) {
        $('#icon-overlay').hide();
        $('#gallery').hide();
    }

    if (!$(target).is('#character-selector') && 
      !$(target).is('#swap-icon') && 
      !$(target).parents().is('#character-selector')) {
        $('#character-selector').hide();
    }

    if (!$(target).is('#post-menu-box') && !$(target).parents().is('#post-menu-box')
      && !$(target).is('#post-menu') && !$(target).parents().is('#post-menu')) {
      $('#post-menu-box').hide();
      $('#post-menu').removeClass('selected');
    }
  });
});

bindGallery = function() {
  $("#gallery img").click(function() {
    id = $(this).attr('id');
    $("#reply_icon_id").val(id);
    $('#icon-overlay').hide();
    $('#gallery').hide();
    $("#current-icon").attr('src', $(this).attr('src'));
    $("#current-icon").attr('title', $(this).attr('title'));
    $("#current-icon").attr('alt', $(this).attr('alt'));
  });
};

bindIcon = function() {
  $('#current-icon-holder').click(function() {
    $('#icon-overlay').toggle();
    $('#gallery').toggle();
    $('html, body').scrollTop($("#post-editor").offset().top);
  });
};

galleryString = function(gallery, multiGallery) {
  var iconsString = "";
  var icons = gallery["icons"];

  for (var i=0; i<icons.length; i++) {
    iconsString += iconString(icons[i]);
  }

  if(!multiGallery) { return iconsString; }

  var nameString = "<div class='gallery-name'>" + gallery['name'] + "</div>"
  return "<div class='gallery-group'>" + nameString + iconsString + "</div>"
};

iconString = function(icon) {
  var img_id = icon["id"];
  var img_url = icon["url"];
  var img_key = icon["keyword"];

  return "<div class='gallery-icon'>"
    + "<img src='" + img_url + "' id='" + img_id + "' alt='" + img_key + "' title='" + img_key + "' class='icon' />"
    + "<br />" + img_key
    + "</div>";
};

tinyMCESetup = function(ed) {
  ed.on('init', function(args) {
    if($("#html").hasClass('selected') == true) {
      tinyMCE.execCommand('mceRemoveEditor', false, 'post_content');
      tinyMCE.execCommand('mceRemoveEditor', false, 'reply_content');
      $(".tinymce").val(gon.original_content);
    } else {
      var rawContent = tinymce.activeEditor.getContent({format: 'raw'});
      var content = tinymce.activeEditor.getContent();
      if (rawContent == '<p>&nbsp;<br></p>' && content == '') { tinymce.activeEditor.setContent(''); }
    };
  });
};

getAndSetCharacterData = function(characterId) {
  // Handle page interactions
  $("#character-selector").hide();
  $("#current-icon-holder").unbind();

  // Handle special case where just setting to your base account
  if (characterId == '') {
    $("#post-editor .post-character").hide();
    $("#post-editor .post-screenname").hide();
    $("#post-editor #post-author-spacer").show();
    var url = gon.current_user.avatar.url;
    if(url != null) {
      var aid = gon.current_user.avatar.id;
      $("#current-icon").attr('src', url).addClass('pointer');
      $("#reply_icon_id").val(aid);
      $("#gallery").html("");
      $("#gallery").append("<div class='gallery-icon'><img src='" + url + "' id='" + aid + "' class='icon' /><br />Avatar</div>");
      $("#gallery").append("<div class='gallery-icon'><img src='/images/no-icon.png' id='' class='icon' /><br />No Icon</div>");
      bindIcon();
      bindGallery();
    }
    return // Don't need to load data from server (TODO combine with below?)
  }

  $.post(gon.character_path, {'character_id':characterId}, function (resp) {
    // Display the correct name/screenname fields
    $("#post-editor #post-author-spacer").hide();
    $("#post-editor .post-character").show().html(resp['name']);
    if(resp['screenname'] == undefined) {
      $("#post-editor .post-screenname").hide();
    } else {
      $("#post-editor .post-screenname").show().html(resp['screenname']);
    }

    // Display no icon if no default set
    if (resp['default'] == undefined) {
      $("#current-icon").attr('src', '/images/no-icon.png').removeClass('pointer');
      $("#reply_icon_id").val('');
      return
    }

    // Display default icon
    $("#current-icon").attr('src', resp['default']['url']).addClass('pointer');
    $("#current-icon").attr('title', resp['default']['keyword']);
    $("#current-icon").attr('alt', resp['default']['keyword']);
    $("#reply_icon_id").val(resp['default']['id']);

    // Calculate new galleries
    $("#gallery").html("");
    var galleries = resp['galleries'];
    if (galleries.length == 0) { return; }

    // Display single gallery
    if (galleries.length == 1) {
      var gallery = galleries[0];
      $("#gallery").append(galleryString(gallery, false));

    // Display multiple galleries
    } else {
      for(var i=0; i<galleries.length; i++) {
        var gallery = galleries[i];
        $("#gallery").append(galleryString(gallery, true));
      }
    }

    // Both single and multiple galleries need these
    $("#gallery").append("<div class='gallery-icon'><img src='/images/no-icon.png' id='' alt='No Icon' title='No Icon' class='icon' /><br />No Icon</div>");
    bindGallery();
    bindIcon();
  });
};
