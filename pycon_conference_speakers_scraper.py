#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
PyCon speakers web-scraper
"""
from __future__ import print_function
import sys, re, warnings, json

import requests
from bs4 import BeautifulSoup
from prettytable import PrettyTable

URL_BASE = "http://il.pycon.org"
URL = URL_BASE + "/wwwpyconIL/speakers"
RE_SPEAKERS = "view-speakersandsession*."

DATA_HANDLES = dict(
    linkedin = 'speaker-linkin',
    twitter = 'speaker-twitter',
    bio = 'speaker-body',
    sessions = 'speaker-word-session',
)

MISSING_SPEAKERS = [
    ( 75,'Moshe Nahmias'),
    (152,'Ori Rabin'),
    (155,'Nadav Goldin')
]

# utility funcs

def _notnull(data, key):
    return '-' if data.get(key) is None else '+'

def _find_parent_div(element, class_):
    for par in element.parents:
        if par.name=='div' and (class_ in par.attrs.get('class')):
            return par
    assert False, 'no parent of class '+class_
    
def _find_unique(element, *args, **kwargs):
    allow_none = kwargs.pop('allow_none', False)
    items = element.find_all(*args, **kwargs)
    if allow_none and len(items)==0:
        return None
    else:
        assert len(items)==1
        return items[0]

def _spacify(s):
    "convert whitespace to single space"
    return ' '.join(s.split())

def _get_link(anchor):
    relative = anchor['href']
    if relative.endswith('%20'):
        relative = relative[:-3]
    return URL_BASE + relative

# extracting data from specific elements

def find_sessions(head):
    content = _find_parent_div(head, 'view-grouping-content')
    anchors = [x.find('a') for x in content.find_all(
        'span', class_='field-content')]
    items = [(x.text, _get_link(x)) for x in anchors]
    return items

def find_speaker_data(speaker, group=None, name=None):
    if group is None: group = speaker
    
    data  = {}
    if name is None:
        name = _spacify(_find_unique(speaker, 'h1').text)
    data['name'] = name
    img_attr = _find_unique(group, 'img').attrs
    if not img_attr['alt']:
        assert 'default_avatar' in img_attr['src']
        data['image'] = None
    else:
        if not _spacify(img_attr['alt']) == data['name']:
            warnings.warn('error in name "{0}"!="{1}"'.format(
                _spacify(img_attr['alt']), data['name']))
        data['image'] = URL_BASE + img_attr['src'].split('?')[0]
    
    for field, cls in DATA_HANDLES.items():
        data[field] = _find_unique(speaker, class_ = cls, allow_none=True)
    
    # post-processing...
    
    for field in ['linkedin', 'twitter']:
        if data[field]:
            a = data[field].find_all('a')[-1]
            data[field] = a['href']

    if data['bio'] is None:
        warnings.warn('missing bio for {0}'.format(data['name']))
        data['bio'] = ''
    else:
        data['bio'] = ''.join([str(x) for x in data['bio'].contents])
    data['sessions'] = find_sessions(data['sessions'])
    
    twit = data['twitter']
    if twit and 'github' in twit:
        data['github'] = twit
        data['twitter'] = None
    else:
        data['github'] = None
    
    return data


if __name__ == "__main__":
    print("[+] Fetching PyCon speakers page...")
    requests_res = requests.get(URL)

    if requests_res.status_code != requests.codes.ok:
        print(
            "[!] Received unexpected HTTP response: %s from website"
            % requests_res
        )
        sys.exit(1)
    
    soup = BeautifulSoup(requests_res.text, "html.parser")
    
    print("[+] parsing...")
    html_elements = soup.find_all(
        name="div", attrs={"class": re.compile(RE_SPEAKERS)}
    )[0]
    speakerlist = _find_unique(html_elements, 'div', class_='view-content')
    db = []
    for head in speakerlist.find_all('h1'):
        if head.text == 'Pycon Israel Team': continue
        
        speaker = _find_parent_div(head, 'view-grouping')
        content = _find_parent_div(head, 'view-grouping-content')
        # several speakers might be packed together as a group with common image
        group = _find_parent_div(content, 'view-grouping')
        db.append(find_speaker_data(speaker, group))
    
    # Now, need to scrape some people who do not appear in the main speakers page
    # (bug in the site: co-speakers were not listed)
    for sid, name in MISSING_SPEAKERS:
        link = URL_BASE + '/wwwpyconIL/speakers_info/{0}'.format(sid)
        print("[+] fetching missing speaker id {0}:".format(sid))
        requests_res = requests.get(link)
        assert requests_res.status_code == requests.codes.ok, "http error"
        print("[+] parsing item {0}:".format(sid))
        soup = BeautifulSoup(requests_res.text, "html.parser")
        cospeaker = _find_unique(soup, 'div', class_='view-co-speakersandsession')
        img = cospeaker.find('img')
        speaker = _find_parent_div(img, 'view-grouping')
        db.append(find_speaker_data(speaker, name=name))

    # print results
    pretty_table = PrettyTable(['Full Name', 'Pic', 'In', 'twit', 'GH', 'sessions', 'bio'])

    for speaker in db:
        pretty_table.add_row([
            speaker['name'],
            _notnull(speaker, 'image'), _notnull(speaker, 'linkedin'),
            _notnull(speaker, 'twitter'), _notnull(speaker, 'github'),
            len(speaker['sessions']), len(speaker['bio'])
        ])
    
    print("[+] Printing results...")
    print(pretty_table)
    
    if len(sys.argv)>1:
        fname = sys.argv[1]
        print("[+] writing output to file {0}...".format(fname))
        json.dump(dict(speakers=db), open(fname, 'w'))
    
    print("[+] Done")
