#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Talks to App Store Connect through its API, with the team key « Color »
(role App Manager): what Apple says of each version and build, a new version
prepared, a version sent for review. No password and no web session.

  app_store_connect.py etat
  app_store_connect.py builds [--plateforme IOS|MAC_OS]
  app_store_connect.py preparer --plateforme IOS --version 1.2.0 --build 43
                                --fiche docs/publication/FICHE-APP-STORE.md
  app_store_connect.py preparer --plateforme IOS --version 1.0.1 --build 40
                                --nouveautes FICHIER [--description FICHIER]
  app_store_connect.py captures --plateforme IOS --version 1.2.0
                                --dossier CAPTURES/fr --langue fr-FR [--essai]
  app_store_connect.py envoyer --plateforme IOS --version 1.2.0 --accord-du-proprietaire

« preparer --fiche » takes every text of the version from the App Store
fiche of the sources — the parts « Description de la 1.2 (fr-FR) »,
« Nouveautés de la 1.2 (fr-FR) », « Texte promotionnel de la 1.2 (fr-FR) »,
the same three with « (en) », and « Notes pour la vérification de la 1.2 » —
and writes them on the pages fr-FR, en-US and en-GB of the version, with its
build, its copyright, the notes for the reviewer (the contact of the version
before when the new one has none) and an automatic release once Apple
accepts it. (Until 1.1.1, small programs of construction-mac/fiche-1.1.1+42
did this; they are folded in here.)

« captures » puts the pictures of a folder (PNG, without alpha, named
iphone-…, ipad-… or mac-…, in the order of their names) in the screenshot
sets of one page of the version, in place of those it had: the iPhone
(2556 × 1179), the iPad 13 inches (2752 × 2064), the Mac (2880 × 1800).
With --essai it only says what it would do.

The key folder holds identifiants.json (key_id, issuer_id, key_file, app_id)
and the private key itself; it is taken from --cle, from the variable
COLOR_CLE_APP_STORE_CONNECT, or beside the folder of this script
(Color-travail/cle-app-store-connect). The private key is read to sign
tokens and is never printed, copied or sent anywhere: only its signatures
leave, to api.appstoreconnect.apple.com.

« envoyer » sends a version to Apple's review: it refuses to run without
--accord-du-proprietaire, which is given only once the owner has said yes to
that very version. Everything else reads, or prepares a version that is not
sent.

Needs Python 3 with PyJWT and cryptography (present in the Linux machine of
the Claude application).
"""
from pathlib import Path
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

API = 'https://api.appstoreconnect.apple.com'
LOCALE = 'fr-FR'
ENGLISH = ('en-US', 'en-GB')
PLATFORMS = ('IOS', 'MAC_OS')
SUPPORT = 'https://alejandrosml.github.io/Color/'
COPYRIGHT = '2026 Alejandro San Martin Lamas'
KEYWORDS_ENGLISH = 'drawing,kids,colouring,coloring,paint,brush,stamp,art,crayon,preschool,sketch'
# The parts of the fiche that make a version, and the most Apple takes.
FICHE_PARTS = {
    'description_fr': ('Description de la {v} (fr-FR)', 4000),
    'whats_new_fr': ('Nouveautés de la {v} (fr-FR)', 4000),
    'promotion_fr': ('Texte promotionnel de la {v} (fr-FR)', 170),
    'description_en': ('Description de la {v} (en)', 4000),
    'whats_new_en': ('Nouveautés de la {v} (en)', 4000),
    'promotion_en': ('Texte promotionnel de la {v} (en)', 170),
    'notes': ('Notes pour la vérification de la {v}', 4000),
}
# Where Apple shows a picture of Color, by its size in pixels (the iPad of
# 13 inches answers, in the API, to the name of the 12.9 inches).
DISPLAY_TYPES = {
    (2556, 1179): ('iphone', 'APP_IPHONE_61'),
    (1179, 2556): ('iphone', 'APP_IPHONE_61'),
    (2752, 2064): ('ipad', 'APP_IPAD_PRO_3GEN_129'),
    (2064, 2752): ('ipad', 'APP_IPAD_PRO_3GEN_129'),
    (2880, 1800): ('mac', 'APP_DESKTOP'),
}
DEVICES_OF = {'IOS': ('iphone', 'ipad'), 'MAC_OS': ('mac',)}
# What Apple calls each state, in the words of the French App Store Connect.
STATES = {
    'PREPARE_FOR_SUBMISSION': 'à finaliser avant soumission',
    'READY_FOR_REVIEW': 'prête pour la vérification',
    'WAITING_FOR_REVIEW': 'en attente de vérification',
    'IN_REVIEW': 'en cours de vérification',
    'PENDING_DEVELOPER_RELEASE': 'acceptée, en attente de publication',
    'READY_FOR_DISTRIBUTION': 'prête pour la distribution (publiée)',
    'REJECTED': 'refusée',
    'METADATA_REJECTED': 'métadonnées refusées',
    'DEVELOPER_REJECTED': 'retirée par le développeur',
    'PROCESSING_FOR_DISTRIBUTION': 'en traitement pour la distribution',
    'ACCEPTED': 'acceptée',
    'INVALID_BINARY': 'binaire refusé',
    'REPLACED_WITH_NEW_VERSION': 'remplacée par une nouvelle version',
}


class _NoRedirection(urllib.request.HTTPRedirectHandler):
    """A token signed with the key goes to the address it was made for and
    to no other: an answer that sends elsewhere is not followed (urllib
    would carry the Authorization header along), it is a refusal."""

    def redirect_request(self, *arguments, **named):
        return None


_DIRECT = urllib.request.build_opener(_NoRedirection)


class Apple:
    """The App Store Connect API, signed with the key of the folder."""

    def __init__(self, folder):
        import jwt  # PyJWT, with cryptography for ES256
        self._jwt = jwt
        identifiers = json.loads((folder / 'identifiants.json').read_text(encoding='utf-8'))
        self.key_id = identifiers['key_id']
        self.issuer_id = identifiers['issuer_id']
        self.app_id = identifiers['app_id']
        self._key = (folder / identifiers['key_file']).read_text(encoding='ascii')
        self._token = None
        self._token_until = 0

    def _authorization(self):
        now = int(time.time())
        if not self._token or now > self._token_until - 60:
            # Apple accepts a token of twenty minutes at most.
            self._token = self._jwt.encode(
                {'iss': self.issuer_id, 'iat': now, 'exp': now + 1200,
                 'aud': 'appstoreconnect-v1'},
                self._key, algorithm='ES256', headers={'kid': self.key_id, 'typ': 'JWT'})
            self._token_until = now + 1200
        return 'Bearer ' + self._token

    def call(self, method, path, body=None, query=None):
        url = API + path
        if query:
            url += '?' + urllib.parse.urlencode(query)
        data = json.dumps(body).encode('utf-8') if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers={
            'Authorization': self._authorization(), 'Content-Type': 'application/json'})
        try:
            with _DIRECT.open(request, timeout=60) as answer:
                text = answer.read().decode('utf-8')
        except urllib.error.HTTPError as error:
            detail = error.read().decode('utf-8', 'replace')
            try:
                errors = json.loads(detail).get('errors', [])
                detail = ' ; '.join('%s : %s' % (e.get('title', ''), e.get('detail', ''))
                                    for e in errors) or detail
            except ValueError:
                pass
            raise SystemExit('App Store Connect a refusé %s %s (HTTP %d) : %s'
                             % (method, path, error.code, detail[:800]))
        except (urllib.error.URLError, OSError) as error:
            # No network, a name that does not resolve, a connection cut:
            # said in one line, with nothing of the request.
            raise SystemExit('App Store Connect n’a pas répondu à %s %s : %s'
                             % (method, path, getattr(error, 'reason', error)))
        return json.loads(text) if text else {}

    def upload(self, operation, data):
        """One part of an asset, sent where Apple said (its own address,
        signed by Apple: no token goes with it)."""
        if not str(operation.get('url') or '').startswith('https://'):
            # urllib would also open file: and ftp: addresses.
            raise SystemExit('Apple a donné pour l’image une adresse qui n’est pas en https.')
        offset, length = operation.get('offset', 0), operation.get('length', len(data))
        headers = {header['name']: header['value']
                   for header in operation.get('requestHeaders') or []}
        request = urllib.request.Request(operation['url'], data=data[offset:offset + length],
                                         method=operation.get('method', 'PUT'), headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=120) as answer:
                answer.read()
        except urllib.error.HTTPError as error:
            raise SystemExit('Apple a refusé une part de l’image (HTTP %d).' % error.code)
        except (urllib.error.URLError, OSError) as error:
            raise SystemExit('Une part de l’image n’est pas arrivée chez Apple : %s'
                             % getattr(error, 'reason', error))

    def versions(self):
        return self.call('GET', '/v1/apps/%s/appStoreVersions' % self.app_id, query={
            'fields[appStoreVersions]': 'platform,versionString,appVersionState,appStoreState,'
                                        'createdDate,releaseType,build',
            'include': 'build', 'fields[builds]': 'version', 'limit': '50'})

    def version(self, platform, version_string):
        for item in self.versions().get('data', []):
            attributes = item['attributes']
            if attributes['platform'] == platform and attributes['versionString'] == version_string:
                return item
        return None

    def builds(self, platform=None, number=None):
        query = {'filter[app]': self.app_id, 'sort': '-uploadedDate', 'limit': '20',
                 'include': 'preReleaseVersion',
                 'fields[builds]': 'version,uploadedDate,processingState,expired,'
                                   'usesNonExemptEncryption,preReleaseVersion',
                 'fields[preReleaseVersions]': 'version,platform'}
        if platform:
            query['filter[preReleaseVersion.platform]'] = platform
        if number:
            query['filter[version]'] = str(number)
        answer = self.call('GET', '/v1/builds', query=query)
        versions = {item['id']: item['attributes'] for item in answer.get('included', [])
                    if item['type'] == 'preReleaseVersions'}
        found = []
        for item in answer.get('data', []):
            link = ((item.get('relationships') or {}).get('preReleaseVersion') or {}).get('data')
            found.append((item, versions.get(link['id']) if link else None))
        return found


def local_time(text):
    """A date of Apple (Pacific time, with its offset) in the time of Paris."""
    if not text:
        return '—'
    try:
        from zoneinfo import ZoneInfo
        moment = datetime.fromisoformat(text.replace('Z', '+00:00'))
        return moment.astimezone(ZoneInfo('Europe/Paris')).strftime('%d/%m/%Y %H:%M')
    except (ValueError, ImportError, KeyError):
        return text[:16].replace('T', ' ')


def state_of(attributes):
    state = attributes.get('appVersionState') or attributes.get('appStoreState') or '?'
    return STATES.get(state, state)


def folder_of(arguments):
    if arguments.cle:
        return Path(arguments.cle)
    if os.environ.get('COLOR_CLE_APP_STORE_CONNECT'):
        return Path(os.environ['COLOR_CLE_APP_STORE_CONNECT'])
    return Path(__file__).resolve().parent.parent / 'cle-app-store-connect'


def show_states(apple):
    answer = apple.versions()
    numbers = {item['id']: item['attributes'].get('version') for item in answer.get('included', [])
               if item['type'] == 'builds'}
    for item in answer.get('data', []):
        attributes = item['attributes']
        link = ((item.get('relationships') or {}).get('build') or {}).get('data')
        build = numbers.get(link['id']) if link else None
        print('%-6s %-7s %-40s build %-4s créée le %s' % (
            'Mac' if attributes['platform'] == 'MAC_OS' else 'iPhone' if attributes['platform'] == 'IOS'
            else attributes['platform'], attributes['versionString'], state_of(attributes),
            build or '—', local_time(attributes.get('createdDate'))[:10]))


def show_builds(apple, platform):
    for item, version in apple.builds(platform):
        attributes = item['attributes']
        print('%-7s %-7s build %-4s %-11s chargé le %s%s' % (
            (version or {}).get('platform', '?'), (version or {}).get('version', '?'),
            attributes.get('version'), attributes.get('processingState'),
            local_time(attributes.get('uploadedDate')),
            ' (expiré)' if attributes.get('expired') else ''))


def quote_after(lines, title):
    """The text quoted (lines that begin with « > ») under the heading
    « ### title » of a fiche."""
    start = next((index for index, line in enumerate(lines)
                  if line.strip() == '### ' + title), None)
    if start is None:
        raise SystemExit('La fiche n’a pas de partie « %s ».' % title)
    block = []
    for line in lines[start + 1:]:
        if line.startswith('#'):
            break
        if line.startswith('>'):
            block.append(line[1:].lstrip(' ') if line.strip() != '>' else '')
        elif block:
            break
    text = '\n'.join(block).strip()
    if not text:
        raise SystemExit('La partie « %s » de la fiche est vide.' % title)
    return text


def short_version(version_string):
    """« 1.2.0 » is « 1.2 » in the titles of the fiche."""
    parts = version_string.split('.')
    return '.'.join(parts[:2]) if len(parts) == 3 and parts[2] == '0' else version_string


def fiche_texts(fiche, version_string):
    """Every text of [version_string] in the fiche, each within what Apple takes."""
    lines = Path(fiche).read_text(encoding='utf-8').split('\n')
    short = short_version(version_string)
    texts = {}
    for key, (title, most) in FICHE_PARTS.items():
        text = quote_after(lines, title.format(v=short))
        if len(text) > most:
            raise SystemExit('« %s » a %d caractères ; Apple en prend %d au plus.'
                             % (title.format(v=short), len(text), most))
        texts[key] = text
    return texts


def notes_for(platform, notes):
    """The notes for the reviewer: on the Mac, the device is the Mac."""
    return notes.replace('nothing leaves the device', 'nothing leaves the Mac') \
        if platform == 'MAC_OS' else notes


def write_page(apple, version_id, locale, attributes, pages):
    """Writes [attributes] on the page [locale] of the version, made when it
    is missing."""
    if locale in pages:
        apple.call('PATCH', '/v1/appStoreVersionLocalizations/%s' % pages[locale]['id'],
                   body={'data': {'type': 'appStoreVersionLocalizations',
                                  'id': pages[locale]['id'], 'attributes': attributes}})
    else:
        apple.call('POST', '/v1/appStoreVersionLocalizations', body={'data': {
            'type': 'appStoreVersionLocalizations', 'attributes': dict(attributes, locale=locale),
            'relationships': {'appStoreVersion': {'data': {
                'type': 'appStoreVersions', 'id': version_id}}}}})
    print('Page %s écrite.' % locale)


def write_review_notes(apple, platform, version_id, notes):
    """The notes for the reviewer, with the contact of the version before
    when the new one has none yet."""
    try:
        detail = apple.call('GET', '/v1/appStoreVersions/%s/appStoreReviewDetail'
                            % version_id).get('data')
    except SystemExit:
        detail = None
    if detail:
        apple.call('PATCH', '/v1/appStoreReviewDetails/%s' % detail['id'], body={'data': {
            'type': 'appStoreReviewDetails', 'id': detail['id'], 'attributes': {'notes': notes}}})
    else:
        earlier = [item for item in apple.versions().get('data', [])
                   if item['attributes']['platform'] == platform and item['id'] != version_id
                   and item['attributes'].get('appStoreState') == 'READY_FOR_SALE']
        if not earlier:
            raise SystemExit('Aucune version publiée dont reprendre le contact pour la vérification.')
        before = apple.call('GET', '/v1/appStoreVersions/%s/appStoreReviewDetail'
                            % earlier[0]['id'])['data']['attributes']
        attributes = {key: before.get(key) for key in (
            'contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail',
            'demoAccountRequired')}
        attributes['notes'] = notes
        apple.call('POST', '/v1/appStoreReviewDetails', body={'data': {
            'type': 'appStoreReviewDetails', 'attributes': attributes,
            'relationships': {'appStoreVersion': {'data': {
                'type': 'appStoreVersions', 'id': version_id}}}}})
    print('Notes pour la vérification écrites.')


def prepare(apple, arguments):
    platform, version_string = arguments.plateforme, arguments.version
    if arguments.fiche:
        texts = fiche_texts(arguments.fiche, version_string)
        whats_new, description = texts['whats_new_fr'], texts['description_fr']
    else:
        if not arguments.nouveautes:
            raise SystemExit('Donner --fiche, ou --nouveautes.')
        texts = None
        whats_new = Path(arguments.nouveautes).read_text(encoding='utf-8').strip()
        description = (Path(arguments.description).read_text(encoding='utf-8').strip()
                       if arguments.description else None)
    if len(whats_new) > 4000:
        raise SystemExit('Les nouveautés dépassent 4 000 caractères.')
    builds = [item for item, version in apple.builds(platform, arguments.build)
              if version and version.get('version') == version_string]
    if not builds:
        raise SystemExit('Aucun build %s de la version %s pour %s chez Apple.'
                         % (arguments.build, version_string, platform))
    build = builds[0]
    if build['attributes'].get('processingState') != 'VALID':
        raise SystemExit('Le build %s n’est pas prêt : %s.'
                         % (arguments.build, build['attributes'].get('processingState')))
    existing = apple.version(platform, version_string)
    if existing:
        version_id = existing['id']
        print('La version %s existe déjà (%s).' % (version_string, state_of(existing['attributes'])))
        apple.call('PATCH', '/v1/appStoreVersions/%s' % version_id, body={'data': {
            'type': 'appStoreVersions', 'id': version_id,
            'attributes': {'releaseType': 'AFTER_APPROVAL', 'copyright': COPYRIGHT}}})
    else:
        created = apple.call('POST', '/v1/appStoreVersions', body={'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': platform, 'versionString': version_string,
                           'releaseType': 'AFTER_APPROVAL', 'copyright': COPYRIGHT},
            'relationships': {'app': {'data': {'type': 'apps', 'id': apple.app_id}}}}})
        version_id = created['data']['id']
        print('Version %s créée.' % version_string)
    apple.call('PATCH', '/v1/appStoreVersions/%s/relationships/build' % version_id,
               body={'data': {'type': 'builds', 'id': build['id']}})
    print('Build %s choisi.' % arguments.build)
    pages = {item['attributes'].get('locale'): item for item in apple.call(
        'GET', '/v1/appStoreVersions/%s/appStoreVersionLocalizations' % version_id).get('data', [])}
    if LOCALE not in pages:
        raise SystemExit('La version n’a pas de page en français (%s).' % LOCALE)
    french = {'whatsNew': whats_new}
    if description:
        french['description'] = description
    if texts:
        french['promotionalText'] = texts['promotion_fr']
    write_page(apple, version_id, LOCALE, french, pages)
    if texts:
        for locale in ENGLISH:
            write_page(apple, version_id, locale, {
                'whatsNew': texts['whats_new_en'], 'description': texts['description_en'],
                'promotionalText': texts['promotion_en'], 'keywords': KEYWORDS_ENGLISH,
                'supportUrl': SUPPORT, 'marketingUrl': SUPPORT}, pages)
        write_review_notes(apple, platform, version_id, notes_for(platform, texts['notes']))
    page = apple.call('GET', '/v1/appStoreVersionLocalizations/%s' % pages[LOCALE]['id'])['data']
    first = (page['attributes'].get('description') or '').split('\n', 1)[0]
    print('Description, première ligne : ' + first)
    print('Prête à envoyer ; rien n’est parti chez Apple.')


def png_facts(path):
    """The width, the height and whether a PNG has an alpha channel, read
    from its header."""
    import struct
    with open(path, 'rb') as file:
        head = file.read(33)
    if head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        raise SystemExit('%s n’est pas une image PNG.' % path)
    width, height = struct.unpack('>II', head[16:24])
    colour_type = head[25]
    return width, height, colour_type in (4, 6)


def pictures_of(folder, platform):
    """The pictures of [folder] for [platform], by display type, in the order
    of their names; refused when one has an alpha channel or a size Apple
    does not take."""
    sets = {}
    for path in sorted(Path(folder).glob('*.png')):
        device = path.name.split('-', 1)[0]
        if device not in DEVICES_OF[platform]:
            continue
        width, height, alpha = png_facts(path)
        if alpha:
            raise SystemExit('%s a un canal alpha : Apple le refuse.' % path.name)
        known = DISPLAY_TYPES.get((width, height))
        if not known or known[0] != device:
            raise SystemExit('%s : %d × %d n’est pas une taille de %s.'
                             % (path.name, width, height, device))
        sets.setdefault(known[1], []).append(path)
    if not sets:
        raise SystemExit('Aucune image pour %s dans %s.' % (platform, folder))
    for display, paths in sets.items():
        if len(paths) > 10:
            raise SystemExit('%d images pour %s : Apple en prend dix au plus.'
                             % (len(paths), display))
    return sets


def put_screenshots(apple, arguments):
    import hashlib
    sets = pictures_of(arguments.dossier, arguments.plateforme)
    for display, paths in sets.items():
        print('%s : %s' % (display, ', '.join(path.name for path in paths)))
    if arguments.essai:
        print('Essai : rien n’est envoyé.')
        return
    version = apple.version(arguments.plateforme, arguments.version)
    if not version:
        raise SystemExit('La version %s n’existe pas pour %s.'
                         % (arguments.version, arguments.plateforme))
    # The pictures it had are deleted first: only for a version that every
    # state Apple gives says is being prepared — one state that says
    # otherwise, or no state at all, and nothing is touched.
    states = {version['attributes'].get(name) for name in ('appStoreState', 'appVersionState')}
    if states - {None} != {'PREPARE_FOR_SUBMISSION'}:
        raise SystemExit('La version %s n’est plus modifiable (%s).'
                         % (arguments.version, state_of(version['attributes'])))
    pages = {item['attributes'].get('locale'): item for item in apple.call(
        'GET', '/v1/appStoreVersions/%s/appStoreVersionLocalizations' % version['id']).get('data', [])}
    if arguments.langue not in pages:
        raise SystemExit('La version n’a pas de page %s.' % arguments.langue)
    page_id = pages[arguments.langue]['id']
    existing = {item['attributes']['screenshotDisplayType']: item for item in apple.call(
        'GET', '/v1/appStoreVersionLocalizations/%s/appScreenshotSets' % page_id).get('data', [])}
    for display, paths in sets.items():
        if display in existing:
            set_id = existing[display]['id']
            # The pictures the new version took from the one before go: the
            # published version keeps its own.
            for old in apple.call('GET', '/v1/appScreenshotSets/%s/appScreenshots'
                                  % set_id).get('data', []):
                apple.call('DELETE', '/v1/appScreenshots/%s' % old['id'])
        else:
            set_id = apple.call('POST', '/v1/appScreenshotSets', body={'data': {
                'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': display},
                'relationships': {'appStoreVersionLocalization': {'data': {
                    'type': 'appStoreVersionLocalizations', 'id': page_id}}}}})['data']['id']
        order = []
        for path in paths:
            data = path.read_bytes()
            reserved = apple.call('POST', '/v1/appScreenshots', body={'data': {
                'type': 'appScreenshots',
                'attributes': {'fileName': path.name, 'fileSize': len(data)},
                'relationships': {'appScreenshotSet': {'data': {
                    'type': 'appScreenshotSets', 'id': set_id}}}}})['data']
            for operation in reserved['attributes'].get('uploadOperations') or []:
                apple.upload(operation, data)
            apple.call('PATCH', '/v1/appScreenshots/%s' % reserved['id'], body={'data': {
                'type': 'appScreenshots', 'id': reserved['id'],
                'attributes': {'uploaded': True,
                               'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
            order.append(reserved['id'])
            print('  %s envoyée.' % path.name)
        apple.call('PATCH', '/v1/appScreenshotSets/%s/relationships/appScreenshots' % set_id,
                   body={'data': [{'type': 'appScreenshots', 'id': item} for item in order]})
        # Apple checks each picture after it arrives: wait for its word.
        for _ in range(60):
            states = [apple.call('GET', '/v1/appScreenshots/%s' % item)['data']['attributes']
                      .get('assetDeliveryState') or {} for item in order]
            if all(state.get('state') == 'COMPLETE' for state in states):
                break
            failed = [state for state in states if state.get('state') == 'FAILED']
            if failed:
                raise SystemExit('Apple a refusé une image de %s : %s'
                                 % (display, failed[0].get('errors')))
            time.sleep(5)
        else:
            raise SystemExit('Apple n’a pas fini de vérifier les images de %s.' % display)
        print('%s : %d images prêtes.' % (display, len(order)))


def send(apple, arguments):
    if not arguments.accord_du_proprietaire:
        raise SystemExit('Envoyer à Apple demande l’accord du propriétaire (--accord-du-proprietaire).')
    version = apple.version(arguments.plateforme, arguments.version)
    if not version:
        raise SystemExit('La version %s n’existe pas pour %s.' % (arguments.version, arguments.plateforme))
    submission = apple.call('POST', '/v1/reviewSubmissions', body={'data': {
        'type': 'reviewSubmissions', 'attributes': {'platform': arguments.plateforme},
        'relationships': {'app': {'data': {'type': 'apps', 'id': apple.app_id}}}}})['data']
    apple.call('POST', '/v1/reviewSubmissionItems', body={'data': {
        'type': 'reviewSubmissionItems', 'relationships': {
            'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission['id']}},
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}}}})
    apple.call('PATCH', '/v1/reviewSubmissions/%s' % submission['id'], body={'data': {
        'type': 'reviewSubmissions', 'id': submission['id'], 'attributes': {'submitted': True}}})
    print('Envoyée à la vérification d’Apple.')
    show_states(apple)


def main():
    parser = argparse.ArgumentParser(description='Color et App Store Connect, par la clé d’API.')
    parser.add_argument('--cle', help='le dossier de la clé')
    commands = parser.add_subparsers(dest='commande', required=True)
    commands.add_parser('etat', help='ce que dit Apple de chaque version')
    listing = commands.add_parser('builds', help='les builds reçus par Apple')
    listing.add_argument('--plateforme', choices=PLATFORMS)
    preparing = commands.add_parser('preparer', help='prépare une version, sans l’envoyer')
    preparing.add_argument('--plateforme', choices=PLATFORMS, required=True)
    preparing.add_argument('--version', required=True)
    preparing.add_argument('--build', required=True)
    preparing.add_argument('--fiche', help='la fiche de l’App Store des sources : tous les textes')
    preparing.add_argument('--nouveautes', help='fichier des nouveautés (sans --fiche)')
    preparing.add_argument('--description', help='fichier de la description, si elle change')
    pictures = commands.add_parser('captures', help='met les captures d’une page de la version')
    pictures.add_argument('--plateforme', choices=PLATFORMS, required=True)
    pictures.add_argument('--version', required=True)
    pictures.add_argument('--dossier', required=True, help='le dossier des images PNG')
    pictures.add_argument('--langue', default=LOCALE, choices=(LOCALE,) + ENGLISH)
    pictures.add_argument('--essai', action='store_true', help='dit ce qui serait fait')
    sending = commands.add_parser('envoyer', help='envoie une version préparée à Apple')
    sending.add_argument('--plateforme', choices=PLATFORMS, required=True)
    sending.add_argument('--version', required=True)
    sending.add_argument('--accord-du-proprietaire', action='store_true')
    arguments = parser.parse_args()
    if arguments.commande == 'captures' and arguments.essai:
        return put_screenshots(None, arguments)
    apple = Apple(folder_of(arguments))
    if arguments.commande == 'etat':
        show_states(apple)
    elif arguments.commande == 'builds':
        show_builds(apple, arguments.plateforme)
    elif arguments.commande == 'preparer':
        prepare(apple, arguments)
    elif arguments.commande == 'captures':
        put_screenshots(apple, arguments)
    else:
        send(apple, arguments)


if __name__ == '__main__':
    sys.exit(main())
