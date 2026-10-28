# Split Club

A small running leaderboard for one community. Plain HTML, CSS and JavaScript;
no runtime packages, paid libraries, build service, runner accounts or work email.
Designed for GitHub Pages and a personal GitHub account.

## Included

- Separate 3K, 5K, 10K and 21.1K leaderboards.
- Fastest elapsed time per runner, competition ties, name search, all-time/current-month filters.
- A run form with calculated pace, date/time validation and optional HTTPS activity link.
- JPG, PNG or WebP screenshot preview and upload (maximum 5 MiB).
- Clearly labelled sample data and tab-local demo submissions when shared storage is unconfigured.
- Optional Supabase shared persistence, anonymous submissions, database-side validation and restricted writes.
- Responsive layout, keyboard controls, native dialogs and no external fonts, analytics or image services.

**Current connection:** `config.js` has empty public settings. The release runs in
demo mode. Demo entries disappear on reload and are not visible to other runners.
GitHub Pages hosts the page; it does not store incoming submissions.

## Run locally

From this folder:

```sh
npm test
npm run build
npm start
```

Open <http://127.0.0.1:4173>. Node 20+ and Python 3 are enough; do not run `npm install`.
`npm run build` also creates `release/index.html`, a self-contained version that
works by opening the file directly and can be uploaded through GitHub's website.
There is no remote font or script download.

## Publish on GitHub Pages

Use your personal GitHub account, not a work organization or work email.
GitHub Free supports Pages for a **public** repository. Keep private screenshots,
credentials and unrelated local files out of the repository.

### Upload through the browser

1. Create a public repository, for example `split-club`.
2. Upload the generated `release/index.html` to the repository root. You may also
   upload this README, the source archive and `supabase/schema.sql` for reference.
3. Commit using your personal GitHub email or your GitHub-provided noreply address.
4. Open **Settings → Pages → Deploy from a branch**, choose `main` and `/ (root)`.
5. GitHub will display the live address, normally
   `https://<your-actual-GitHub-username>.github.io/split-club/`.

After changing the source or connection settings, rebuild and upload the new
`release/index.html`. A new run in connected mode is saved directly to shared
storage; it does not need a repository commit or redeployment.

### Keep the full source in Git

The included `.github/workflows/pages.yml` tests, builds and publishes `dist/`
after pushes to `main`. Select **GitHub Actions** as the Pages source for this
workflow. Pull requests run checks but cannot deploy. The public repository does
not require a paid Actions plan. Node is only a local/CI tool; the website is static.

## Enable shared submissions

This is the only external service needed for participants to save runs themselves.
It requires an existing Supabase project under your personal account. Check the
current free-plan limits at <https://supabase.com/pricing>; no billing or paid
upgrade is needed by the code. This project does not create accounts or accept
terms on your behalf.

1. Run `supabase/schema.sql` in that project's SQL Editor. Use a new project to
   avoid unrelated policies granting broader access.
2. Find the project's HTTPS URL and **publishable** API key. Only a key beginning
   `sb_publishable_` is accepted. Never use a secret or service-role key.
3. Put the public settings in `config.js`:

```js
window.RUN_CLUB_CONFIG = Object.freeze({
  supabaseUrl: "https://YOUR-PROJECT.supabase.co",
  publishableKey: "sb_publishable_YOUR-PUBLIC-KEY"
});
```

4. Test locally, rebuild and publish. The banner changes from demo to community
   leaderboard. No participant needs a Supabase account or GitHub account.
5. Test from two separate browsers: submit a run in one, refresh the other and
   check it appears. Try a screenshot and check its proof opens.

Supabase reads are paginated. The app refreshes when returning to the tab and
every minute while visible. A failed connection shows an error, never sample
results masquerading as shared data.

## Group rules and organizer tasks

- Names identify runners. Use exactly the same name each time. Names are
  unverified; two people with the same name should add distinguishing initials.
- Use elapsed completion time including pauses, and the actual distance result.
  A longer run's average pace is not proof of a shorter-distance performance.
- A 21.1K category is a rounded recreational half-marathon category, not official
  race certification. Screenshots support a claim; the app does not extract or verify their text.
- Runs and screenshot URLs are public. Crop maps and private information before uploading.
- The organizer corrects/deletes records and removes screenshots through the
  protected Supabase dashboard. Removing a run does not automatically remove its image.
- Anonymous clients may read runs and call the validated `submit_run` function.
  They cannot directly insert, edit or delete run rows or overwrite screenshots.
- A convenience limit allows 10 submissions per name per UTC day. It is not bot
  protection: anyone can choose another name. Anonymous image uploads can consume
  storage independently. Monitor quota and remove abandoned uploads; suspend
  writes using the statements at the end of `schema.sql` if needed.
- The first release reads at most 5,000 runs and reports a visible error above
  that limit so it cannot silently show an incomplete ranking. Archive older runs
  or move aggregation server-side if the community outgrows this.

## Validation

`npm test` uses Node's built-in test runner. Tests cover category isolation,
personal bests, ties, calendar dates, rounding, name search, safe CSV cells,
storage pagination, publishable-key restrictions and screenshot requests.
The SQL must also be run and checked in the chosen Supabase project before
calling shared submissions live; Node tests do not substitute for live SQL checks.

The sample runners are fictional. All source and illustrations are created for
this project. There is no tracking, payment flow, Strava OAuth or OCR integration.
