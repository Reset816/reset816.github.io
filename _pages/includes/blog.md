# 📝 Blog

Articles in English
{% for part in site.en%}
  - [{{ part.title }}]({{part.url}})
{% endfor %}

Articles in Chinese
{% for part in site.cn%}
  - [{{ part.title }}]({{part.url}})
{% endfor %}
