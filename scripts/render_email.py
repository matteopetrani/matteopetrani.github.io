#!/usr/bin/env python3
"""
Render a Jekyll markdown post into a full email HTML.
Usage: python3 render_email.py <post_file> <post_url> <unsub_url> <unsub_label>
Outputs HTML to stdout.
"""
import sys
import os
import re
import markdown as md_lib

def strip_frontmatter(text):
    """Return the body of a Jekyll post, stripping YAML frontmatter."""
    lines = text.splitlines(keepends=True)
    if not lines or not lines[0].startswith('---'):
        return text
    end = None
    for i, line in enumerate(lines[1:], 1):
        if line.startswith('---'):
            end = i
            break
    if end is None:
        return text
    return ''.join(lines[end + 1:])

def get_frontmatter_value(text, key):
    for line in text.splitlines():
        if line.startswith(key + ':'):
            value = line[len(key) + 1:].strip().strip('"')
            return value
    return ''

def markdown_to_html(markdown_text):
    return md_lib.markdown(markdown_text, extensions=['extra'])

def inline_styles(html):
    html = re.sub(r'<p>',          r'<p style="margin:0 0 1.4em 0">',                                                              html)
    html = re.sub(r'<h2>',         r'<h2 style="font-weight:400;font-size:1.3em;margin:2em 0 0.5em 0">',                           html)
    html = re.sub(r'<h3>',         r'<h3 style="font-weight:400;font-size:1.1em;margin:1.5em 0 0.5em 0">',                         html)
    html = re.sub(r'<a ',          r'<a style="color:#222222" ',                                                                    html)
    html = re.sub(r'<blockquote>', r'<blockquote style="border-left:2px solid #ccc;margin:1.5em 0;padding:0 0 0 20px;color:#555">', html)
    html = re.sub(r'<ul>',         r'<ul style="padding-left:1.5em;margin:0 0 1.4em 0">',                                          html)
    html = re.sub(r'<ol>',         r'<ol style="padding-left:1.5em;margin:0 0 1.4em 0">',                                          html)
    html = re.sub(r'<li>',         r'<li style="margin-bottom:0.4em">',                                                             html)
    html = re.sub(r'<hr\s*/?>',    r'<hr style="border:none;border-top:1px solid #e0dbd3;margin:2em 0">',                          html)
    return html

def render(post_file, post_url, unsub_url, unsub_label):
    with open(post_file) as f:
        raw = f.read()

    title    = get_frontmatter_value(raw, 'title')
    date_str = get_frontmatter_value(raw, 'date')[:10]  # YYYY-MM-DD
    body_md  = strip_frontmatter(raw)
    body_html = inline_styles(markdown_to_html(body_md))

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{{font-family:Georgia,"Times New Roman",Times,serif;background:#ffffff;color:#222222;margin:0;padding:0;font-size:20px;line-height:1.7}}
.wrapper{{max-width:600px;margin:0 auto;padding:48px 32px}}
h1{{font-family:Georgia,"Times New Roman",Times,serif;font-weight:400;font-size:2em;line-height:1.2;margin:0 0 12px 0;color:#222222}}
.meta{{font-size:0.75em;color:#888888;margin:0 0 2em 0;font-family:monospace}}
.footer{{margin-top:3em;padding-top:1.5em;border-top:1px solid #e0dbd3;font-size:0.75em;color:#999999}}
.footer a{{color:#999999}}
</style>
</head>
<body>
<div class="wrapper">
  <h1>{title}</h1>
  <p class="meta">{date_str}</p>
  <div class="content">{body_html}</div>
  <div class="footer"><a href="{unsub_url}">{unsub_label}</a></div>
</div>
</body>
</html>"""

if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <post_file> <post_url> <unsub_url> <unsub_label>", file=sys.stderr)
        sys.exit(1)
    print(render(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]))
