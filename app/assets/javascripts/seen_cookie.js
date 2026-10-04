/*
 * Marks this browser as one that has been here before.
 *
 * AnonLoadShed sheds a page load with no cookie sooner than one with a cookie:
 * a real reader sends one from their second page on, and the scrape never
 * does. A shareable page sets no cookie from the server, because a Set-Cookie
 * would make it unshareable (see AnonCacheable). So the browser sets this one
 * itself. The server never reads its value; only its presence matters.
 */
(function() {
  if (document.cookie.split('; ').some((cookie) => cookie.startsWith('glowfic_seen='))) { return; }
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  document.cookie = `glowfic_seen=1; Max-Age=31536000; Path=/; SameSite=Lax${secure}`;
}());
