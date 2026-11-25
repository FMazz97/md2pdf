-- export.lua: Pandoc filter for the PDF export (run by build-pdf.ps1, one file at a time)

local fpath = ''      -- Markdown file being processed (e.g. chapters/01-x.md), passed with -M filepath=
local exported = {}   -- set of files included in the PDF (environment variable EXPORT_FILES)
local root = os.getenv('EXPORT_ROOT') or ''
-- Zones excluded from the PDF: names of the markers (HTML comments) passed by build-pdf.ps1.
-- The two names must differ and neither may contain the other.
local excl_start = os.getenv('EXPORT_EXCLUDE_START') or ''
local excl_stop = os.getenv('EXPORT_EXCLUDE_STOP') or ''

-- Normalizes a relative path: drops "." and resolves ".."
local function norm(p)
  local parts = {}
  for seg in p:gmatch('[^/]+') do
    if seg == '..' then table.remove(parts)
    elseif seg ~= '.' then table.insert(parts, seg) end
  end
  return table.concat(parts, '/')
end

-- Must match Get-Id in build-pdf.ps1
local function id_of(p)
  local s = p:gsub('%.md$', '')
  s = s:gsub('[/ ]', '-')
  return s:lower()
end

local function dir_of(p) return p:match('^(.*)/[^/]*$') or '' end

local function is_external(t)
  return t:match('^%a[%w+.-]*:') ~= nil or t:match('^//') ~= nil
end

-- Local images: absolute file:// path (only used by the browser to load them; not visible in the PDF)
local function resolve_src(src)
  if is_external(src) then return src end
  local p = (src:sub(1, 1) == '/') and norm(src) or norm(dir_of(fpath) .. '/' .. src)
  local url = ('file://' .. root .. '/' .. p):gsub(' ', '%%20')
  return url
end

local function unescape(s)
  s = s:gsub('&quot;', '"'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&')
  return s
end

local alerts = {
  NOTE = {'note', 'Note'}, TIP = {'tip', 'Tip'}, IMPORTANT = {'important', 'Important'},
  WARNING = {'warning', 'Warning'}, CAUTION = {'caution', 'Caution'},
}

return {
  -- 1) Metadata reading (must happen before everything else)
  {
    Meta = function(meta)
      fpath = meta.filepath and pandoc.utils.stringify(meta.filepath) or ''
      for line in (os.getenv('EXPORT_FILES') or ''):gmatch('[^\r\n]+') do
        exported[norm(line)] = true
      end
    end,
  },

  -- 1b) Excluded zones: everything between <!--START_...--> and <!--STOP_...--> (also inside lists or quotes)
  {
    Blocks = function(blocks)
      if excl_start == '' or excl_stop == '' then return nil end
      local function marker(b)
        if b.t == 'RawBlock' and b.format == 'html' then
          if b.text:find(excl_stop, 1, true) then return 'stop' end
          if b.text:find(excl_start, 1, true) then return 'start' end
        end
        return nil
      end
      local out, skipping, changed = pandoc.List(), false, false
      for _, b in ipairs(blocks) do
        local m = marker(b)
        if m == 'start' then skipping, changed = true, true
        elseif m == 'stop' then skipping, changed = false, true
        elseif skipping then changed = true
        else out:insert(b) end
      end
      if skipping then
        io.stderr:write('[export.lua] WARNING: ' .. excl_start .. ' without ' .. excl_stop .. ' in ' .. fpath ..
          ': excluded up to the end of the block\n')
      end
      if changed then return out end
      return nil
    end,
  },

  -- 2) Transformations
  {
    -- Relative links: become internal PDF navigation; links to files not included (LICENSE, assets/, ...) become plain text
    Link = function(l)
      local t = l.target
      if is_external(t) or t:sub(1, 1) == '#' then return nil end  -- web/mailto links and same-file anchors: unchanged
      local path, frag = t:match('^([^#]*)#?(.*)$')
      path = path:gsub('%%20', ' ')
      frag = frag:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
      local target = (path:sub(1, 1) == '/') and norm(path) or norm(dir_of(fpath) .. '/' .. path)
      if exported[target] then
        local href = '#' .. id_of(target) .. (frag ~= '' and ('--' .. frag) or '')
        local out = pandoc.List({ pandoc.RawInline('html', '<a href="' .. href .. '">') })
        out:extend(l.content)
        out:insert(pandoc.RawInline('html', '</a>'))
        return out
      end
      return l.content
    end,

    Image = function(img)
      img.src = resolve_src(img.src)
      return img
    end,

    -- <p align="center"><img ...></p> (raw HTML) -> plain image without links; HTML comments removed
    RawBlock = function(b)
      if b.format ~= 'html' then return nil end
      local t = b.text
      if t:match('<img') then
        local src = t:match('<img[^>]-src="([^"]*)"')
        if src then
          local alt = unescape(t:match('<img[^>]-alt="([^"]*)"') or '')
          local width = t:match('<img[^>]-width="?(%d+)')
          local attrs = width and { width = width } or {}
          local img = pandoc.Image({ pandoc.Str(alt) }, resolve_src(src), '', pandoc.Attr('', {}, attrs))
          return pandoc.Div({ pandoc.Para({ img }) }, pandoc.Attr('', { 'cover' }))
        end
      end
      local stripped = t:gsub('<!%-%-.-%-%->', '')
      if stripped ~= t then
        if stripped:match('^%s*$') then return {} end
        return pandoc.RawBlock('html', stripped)
      end
      return nil
    end,

    -- GitHub alerts (> [!NOTE]) with an optional custom title on the same line as the marker:
    -- converted here into <div class="note"><div class="title">...</div>...</div>
    BlockQuote = function(bq)
      local first = bq.content[1]
      if not first or (first.t ~= 'Para' and first.t ~= 'Plain') then return nil end
      local kind = pandoc.utils.stringify(first):match('^%[!(%u+)%]')
      local def = kind and alerts[kind]
      if not def then return nil end

      -- First line = marker + optional custom title ("> [!NOTE] My title"); the rest is the body
      local inl, i = first.content, 1
      local line = pandoc.List()
      while i <= #inl and inl[i].t ~= 'SoftBreak' and inl[i].t ~= 'LineBreak' do
        line:insert(inl[i])
        i = i + 1
      end
      local rest = pandoc.List()
      for j = i + 1, #inl do rest:insert(inl[j]) end

      local consumed, mlen = 0, #('[!' .. kind .. ']')
      while #line > 0 and consumed < mlen do
        consumed = consumed + #pandoc.utils.stringify(line[1])
        table.remove(line, 1)
      end
      while #line > 0 and line[1].t == 'Space' do table.remove(line, 1) end

      local title_inlines = (#line > 0) and line or pandoc.List({ pandoc.Str(def[2]) })
      local blocks = pandoc.List({
        pandoc.Div({ pandoc.Para(title_inlines) }, pandoc.Attr('', { 'title' })),
      })
      if #rest > 0 then blocks:insert(pandoc.Para(rest)) end
      for k = 2, #bq.content do blocks:insert(bq.content[k]) end
      return pandoc.Div(blocks, pandoc.Attr('', { def[1] }))
    end,
  },
}
