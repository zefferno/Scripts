#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
PyCon agenda web-scraper
"""
from __future__ import print_function
import sys, json
import os.path, tempfile, cPickle

import requests
from bs4 import BeautifulSoup
from prettytable import PrettyTable

URL_BASE = "http://il.pycon.org"
URL_TABLE = URL_BASE + "/wwwpyconIL/agenda-table"

# string/dict utils

def _notnull(data, key):
    return '-' if data.get(key) is None else '+'

def _spacify(s):
    "convert whitespace to single space"
    return ' '.join(s.split())

def _unprefix(s, prefix):
    assert s.startswith(prefix)
    return s[len(prefix):]

def _filter_prefix(strings, prefix):
    return [x for x in strings if x.startswith(prefix)]

def _find_and_unprefix(strings, prefix):
    good = _filter_prefix(strings, prefix)
    assert len(good)==1
    return _unprefix(good[0], prefix)

# DOM utils

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

def _get_link(anchor):
    relative = anchor['href']
    if relative.endswith('%20'):
        relative = relative[:-3]
    return URL_BASE + relative

def _join_contents(tag):
    return ''.join(str(x) for x in tag.contents)

# data extraction

def get_session_data(sid, div):
    data = {}
    data['sessionId'] = sid

    li = div.find('li')
    data['type'] = _find_and_unprefix(li['class'], 'session-type-')
    # patch up one bad type:
    if data['type']=='Coffee': data['type']=='Break'
    data['track'] = div.find('h3').text.strip()

    # extract the fields
    flds = {}
    for field in li.find_all('div', class_='views-field'):
        key = _find_and_unprefix(field['class'], 'views-field-')
        val = _find_unique(field, class_='field-content', allow_none=True)
        if val:
            flds[key] = val
    
    # extract info from flds
    data['body'] = _join_contents(flds['body'])
    data['title'] = flds['title'].find('h3').text
    data['location'] = _join_contents(flds['field-session-location'])
    vid = flds.get('field-session-video')
    data['video'] = None if not vid else vid.find('iframe')['src']
    
    t = flds['field-session-date'].find('time')
    data['time'] = t.text
    w = t.next_sibling.split()
    data['duration'] = w[w.index('Duration:')+1]
    
    speakers = []
    for field in _filter_prefix(flds.keys(), 'field-ref-speaker-'):
        vals = flds[field].contents
        if not vals: continue
        a = vals[0]
        assert len(vals)==1 and vals[0].name=='a'
        speakers.append( (_spacify(a.text), URL_BASE+a['href']) )
    
    data['speakers'] = speakers
    return data


if __name__ == "__main__":
    print("[+] Fetching PyCon agenda page...")
    requests_res = requests.get(URL_TABLE)

    if requests_res.status_code != requests.codes.ok:
        print(
            "[!] Received unexpected HTTP response: %s from website"
            % requests_res
        )
        sys.exit(1)
    
    soup = BeautifulSoup(requests_res.text, "html.parser")
    heads = soup.find_all('h3', class_='field-content')
    
    print("[+] parsing...")
    links = [_get_link(x.find('a')) for x in heads]
    print("[+] {0} items found.".format(len(links)))
    
    cache = {}
    cachepath = os.path.join(tempfile.gettempdir(),"pyconil_agenda_cache.pickle")
    if os.path.isfile(cachepath):
        cache = cPickle.load(open(cachepath,"rb"))
    else:
        cache = {}

    sessions = []
    try:
        
        for link in links:
            sid = int(link.split('/')[-1])
            if sid not in cache:
                print("[+] fetching agenda item {0}:".format(sid))
                requests_res = requests.get(link)
                assert requests_res.status_code == requests.codes.ok, "http error"
                print("[+] parsing item {0}:".format(sid))
                soup = BeautifulSoup(requests_res.text, "html.parser")
                div = _find_unique(soup, 'div', class_='sessions-track-col')
                cache[sid] = get_session_data(sid, div)
            
            sessions.append(cache[sid])
                
    except (IOError, KeyboardInterrupt, AssertionError), e:
        print("[-] Error, saving cache...")
        cPickle.dump(cache, open(cachepath,"wb"))
        raise e
    else:
        cPickle.dump(cache, open(cachepath,"wb"))

    # pretty print
    locations = sorted(set(x['location'] for x in sessions))
    pretty_table = PrettyTable(['time','duration','title', 'type', 'location', 'body', 'speakers', 'video', 'track'])

    for session in sessions:
        pretty_table.add_row([
            session['time'], session['duration'],
            session['title'][:10],
            session['type'], locations.index(session['location']),
            len(session['body']), len(session['speakers']), 
            _notnull(session, 'video'), session['track']
        ])
    
    print("[+] Printing results...")
    print(pretty_table)

    # save
    if len(sys.argv)>1:
        fname = sys.argv[1]
        print("[+] writing output to file {0}...".format(fname))
        json.dump(dict(sessions=sessions), open(fname, 'w'))
    
    print("[+] Done")
