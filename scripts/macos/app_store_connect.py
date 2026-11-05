#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Talks to App Store Connect through its API, with the team key « Color »
(role App Manager): what Apple says of each version and build, a new version
prepared, a version sent for review. No password and no web session.

  app_store_connect.py etat
  app_store_connect.py builds [--plateforme IOS|MAC_OS]
  app_store_connect.py preparer --plateforme IOS --version 1.0.1 --build 40
                                --nouveautes FICHIER [--description FICHIER]
  app_store_connect.py envoyer --plateforme IOS --version 1.0.1 --accord-du-proprietaire

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
PLATFORMS = ('IOS', 'MAC_OS')
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
            with urllib.request.urlopen(request, timeout=60) as answer:
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
        return json.loads(text) if text else {}

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


def prepare(apple, arguments):
    platform, version_string = arguments.plateforme, arguments.version
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
    else:
        created = apple.call('POST', '/v1/appStoreVersions', body={'data': {
            'type': 'appStoreVersions',
            'attributes': {'platform': platform, 'versionString': version_string,
                           'releaseType': 'AFTER_APPROVAL'},
            'relationships': {'app': {'data': {'type': 'apps', 'id': apple.app_id}}}}})
        version_id = created['data']['id']
        print('Version %s créée.' % version_string)
    apple.call('PATCH', '/v1/appStoreVersions/%s/relationships/build' % version_id,
               body={'data': {'type': 'builds', 'id': build['id']}})
    print('Build %s choisi.' % arguments.build)
    localizations = apple.call('GET', '/v1/appStoreVersions/%s/appStoreVersionLocalizations'
                               % version_id).get('data', [])
    french = [item for item in localizations if item['attributes'].get('locale') == LOCALE]
    if not french:
        raise SystemExit('La version n’a pas de page en français (%s).' % LOCALE)
    attributes = {'whatsNew': whats_new}
    if description:
        attributes['description'] = description
    apple.call('PATCH', '/v1/appStoreVersionLocalizations/%s' % french[0]['id'], body={'data': {
        'type': 'appStoreVersionLocalizations', 'id': french[0]['id'], 'attributes': attributes}})
    print('Nouveautés écrites%s.' % (', description aussi' if description else ''))
    page = apple.call('GET', '/v1/appStoreVersionLocalizations/%s' % french[0]['id'])['data']
    first = (page['attributes'].get('description') or '').split('\n', 1)[0]
    print('Description, première ligne : ' + first)
    print('Prête à envoyer ; rien n’est parti chez Apple.')


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
    preparing.add_argument('--nouveautes', required=True, help='fichier des nouveautés')
    preparing.add_argument('--description', help='fichier de la description, si elle change')
    sending = commands.add_parser('envoyer', help='envoie une version préparée à Apple')
    sending.add_argument('--plateforme', choices=PLATFORMS, required=True)
    sending.add_argument('--version', required=True)
    sending.add_argument('--accord-du-proprietaire', action='store_true')
    arguments = parser.parse_args()
    apple = Apple(folder_of(arguments))
    if arguments.commande == 'etat':
        show_states(apple)
    elif arguments.commande == 'builds':
        show_builds(apple, arguments.plateforme)
    elif arguments.commande == 'preparer':
        prepare(apple, arguments)
    else:
        send(apple, arguments)


if __name__ == '__main__':
    sys.exit(main())
