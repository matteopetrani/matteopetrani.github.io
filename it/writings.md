---
layout: page
title: Writings
permalink: /writings/
---

<div class="writings">
  {% assign posts_for_lang = site.posts | where: "lang", page.lang %}
  {% assign posts_by_year = posts_for_lang | group_by_exp: 'post', "post.date | date: '%Y'" %}
  {% assign sorted_years = posts_by_year | sort: 'name' | reverse %}
  {% for year in sorted_years %}
  <section class="writings-year">
    <h2>{{ year.name }}</h2>
    <ul class="post-list">
      {% assign entries = year.items | sort: 'date' | reverse %}
      {% for post in entries %}
      <li>
        <span class="post-meta">{{ post.date | date: "%Y-%m-%d" }}</span>
        <a class="post-link" href="{{ post.url | relative_url }}">{{ post.title | escape }}</a>
      </li>
      {% endfor %}
    </ul>
  </section>
  {% endfor %}
</div>
