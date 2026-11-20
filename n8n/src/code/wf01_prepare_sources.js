// Wejście: wynik rpc/get_sources_due. Wyjście: jedno zadanie pobrania na źródło (bez Gmail).
return $input.all()
  .map((i) => i.json)
  .filter((s) => s && s.id && s.url && !['gmail', 'x', 'linkedin'].includes(s.type))
  .map((s) => ({ json: s }));
