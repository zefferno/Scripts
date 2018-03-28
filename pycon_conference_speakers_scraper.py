#! /usr/bin/python
# -*- coding: utf-8 -*-

"""
PyCon speakers web-scraper
"""

import re

import requests
from bs4 import BeautifulSoup
from prettytable import PrettyTable

URL = "http://il.pycon.org/wwwpyconIL/speakers"
RE_SPEAKERS = "view-speakersandsession*."

if __name__ == "__main__":
    pretty_table = PrettyTable(['Full Name', 'Picture'])

    print("[+] Fetching PyCon speakers page...")
    requests_res = requests.get(URL)

    if requests_res.status_code != requests.codes.ok:
        print(
            "[!] Received unexpected HTTP response: %s from website"
            % requests_res
        )
        exit(0)

    soup = BeautifulSoup(requests_res.text, "html.parser")

    html_elements = soup.find_all(
        name="div", attrs={"class": re.compile(RE_SPEAKERS)}
    )[0]

    img_list = [img for img in html_elements.find_all("img")]

    for img in img_list:
        name = " ".join(img.get("alt").split())
        picture_url = img.get("src").strip()
        if name and picture_url:
            pretty_table.add_row([name, picture_url])

    print("[+] Printing results...")
    print(pretty_table)

    print("[+] Done")
