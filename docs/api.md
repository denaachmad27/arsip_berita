## Edge Functions API

### POST extract-metadata

Body:
```
{ "url": "https://example.com/article" }
```

Response:
```
{
  "url": "https://example.com/article",
  "canonical_url": "https://example.com/article",
  "title": "Title",
  "og_title": "OpenGraph Title",
  "og_description": "OpenGraph Description",
  "excerpt": "Short summary"
}
```

### POST dedupe-check

Body:
```
{ "url": "https://example.com/article" }
```
or
```
{ "canonical_url": "https://example.com/article" }
```

Response:
```
{ "exists": true, "canonical_url": "https://example.com/article" }
```

