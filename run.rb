# NOTE: Following MUST be done before you start:
# 0) Put phone in Do Not Disturb mode (notifications will interrupt screenshots)
# 1) Start Pokemon Go
# 2) Start Poke Genie
# 3) Set coordinates below to Poke Genie's location (if you moved it)
# 4) Open Pokemon list (and make sure it won't go black e.g. by tilting the phone upside down)
# 5) Set desired sort order and/or filters in Pokemon Go
# 6) Set the number of Pokemon to process below
# 7) Hide keyboard on phone if it is visible
# 8) Scroll to VERY TOP of Pokemon list
# 7) RUN

require 'oily_png'
Loc = Struct.new(:x, :y)
SSLoc = Struct.new(:loc, :color)

# STEP 3 - Adjust the coordinates below if you have it in a different location
POKEGENIE_LOC = Loc.new(1300, 1370)

# STEP 6 - How many Pokemon to process
POKEMON_START = 1
POKEMON_MAX = 30

# DO NOT EDIT BELOW HERE UNLESS YOUR UI SETTINGS ARE DIFFERENT
# (e.g. different phone)

# Pokemon list settings
POKELIST_LOC = Loc.new(300, 900)
POKELIST_LOC_DELTA = Loc.new(400, 500)
POKELIST_PERCOL = 3

# Auto scroll settings
POKELIST_SCROLL_ROWSTART = 4
POKELIST_SCROLL_DY_EVEN = 314
POKELIST_SCROLL_DY_ODD = 313
POKELIST_SCROLL_DELAY = 800

# Other UI settings
POKEMON_INFO_CLOSE_LOC = Loc.new(730, 2800)
POKEMON_INFO_MENU_LOC = Loc.new(1250, 2800)
POKEMON_INFO_APPRAISE_LOC = Loc.new(1250, 2260)
POKEMON_INFO_APPRAISE_DISMISS_LOC = Loc.new(1030, 1850)
POKEGENIE_DISMISS_LOC = Loc.new(125, 230)
POKEMON_INFO_RENAME_LOC = Loc.new(720, 1230)
POKEMON_INFO_RENAME_OK_LOC = Loc.new(700, 1600)
POKEMON_NAME_LENGTH = 12

# Screenshot coordinates to check whether an operation succeeded
SCREENSHOT_POKELIST = SSLoc.new(Loc.new(760, 350), '#fbfffaff') # white background of list
SCREENSHOT_POKEMON_INFO = SSLoc.new(Loc.new(680, 2800), '#1c8796ff') # green background of close button
SCREENSHOT_POKEMON_MENU = SSLoc.new(Loc.new(100, 200), '#4ab483ff') # greenish gradient for menu background
SCREENSHOT_POKEMON_APPRAISE_INITIAL = SSLoc.new(Loc.new(100, 2600), '#ffffffff') # white background of textbox
SCREENSHOT_POKEMON_APPRAISE_BARS = SSLoc.new(Loc.new(660, 2130), '#ffffffff') # white background of appraisal bars
SCREENSHOT_POKEGENIE = SSLoc.new(Loc.new(125, 226), '#455a64ff') # gray X of close button
SCREENSHOT_RENAME = SSLoc.new(Loc.new(1150, 1620), '#43d0a5ff') # greenish background of OK button

# Keycode settings - see https://developer.android.com/reference/android/view/KeyEvent#constants_1
KEYCODE_BACKSPACE = 67
KEYCODE_PASTE = 279

# ADB settings
ADB_SEND_ENABLE = true
ADB_SCREENSHOT_VERIFY_ENABLE = true
ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS = 10
ADB_SCREENSHOT_VERIFY_RETRY_DELAY = 4

# Miscellaneous delays (in seconds)
DELAY_NO_VERIFY = 0.6
DELAY_VERIFY = 1
DELAY_SLOW = 3
DELAY_NONE = 0
DELAY_SCROLL = 4

def adb_verify_screenshot(ssloc)
  unless ADB_SCREENSHOT_VERIFY_ENABLE
    return
  end

  for attempt in 1..ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS do
    pngname = "#{Dir.getwd}/temp.png"
    `adb exec-out screencap -p > #{pngname}`
    unless $?.success?
      throw 'adb_verify_screenshot failed - ' + $?.exitstatus
    end
    image = ChunkyPNG::Image.from_file(pngname)
    pixel = image.get_pixel(ssloc.loc.x, ssloc.loc.y)
    hex = ChunkyPNG::Color.to_hex(pixel)
    exp = ChunkyPNG::Color.from_hex(ssloc.color)

    File.delete(pngname)
    if pixel == exp
      return
    end

    delay = attempt <= 2 ? ADB_SCREENSHOT_VERIFY_RETRY_DELAY / 2 : ADB_SCREENSHOT_VERIFY_RETRY_DELAY
    puts ">> Screenshot validation failed - was #{hex} but expected #{ssloc.color}, waiting #{delay} sec, attempt #{attempt} of #{ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS}"
    sleep(delay)
  end
  throw "Screenshot validation failure exceeded retry attempts. Maybe the game locked up or the servers went down? Start again manually."
end

def adb_tap(loc, wait)
  puts("adb_tap #{loc.x} #{loc.y}")
  if ADB_SEND_ENABLE
    `adb shell input tap #{loc.x} #{loc.y}`
  end
  unless $?.success?
    throw 'adb_tap failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_swipe(start, finish, duration, wait)
  puts "adb_swipe #{start.x} #{start.y} #{finish.x} #{finish.y} #{duration}"
  if ADB_SEND_ENABLE
    `adb shell input swipe #{start.x} #{start.y} #{finish.x} #{finish.y} #{duration}`
  end
  unless $?.success?
    throw 'adb_swipe failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_key(keycode, wait)
  puts "adb_key #{keycode}"
  if ADB_SEND_ENABLE
    `adb shell input keyevent #{keycode}`
  end
  unless $?.success?
    throw 'adb_key failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_key_repeat(keycode, repeat, wait)
  puts "adb_key_repeat #{keycode} x#{repeat}"
  if repeat < 2 # no repeat
    adb_key(keycode, wait)
    return
  end

  if ADB_SEND_ENABLE
    adb_raw = "input keyevent #{keycode}"
    adb_cmd = adb_raw
    for i in 1..repeat
      adb_cmd = "#{adb_cmd} && #{adb_raw}"
    end
    `adb shell "#{adb_cmd}"`
  end
  unless $?.success?
    throw 'adb_key_repeat failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def list_x(col)
  return POKELIST_LOC.x + col * POKELIST_LOC_DELTA.x
end

def list_y(row)
  return POKELIST_LOC.y + row * POKELIST_LOC_DELTA.y
end

row_even = true
adb_verify_screenshot(SCREENSHOT_POKELIST) # make sure we start out in the list
for i in POKEMON_START-1..POKEMON_MAX-1 do
  puts "Scanning #{i+1} of #{POKEMON_MAX}"
  row = i / POKELIST_PERCOL
  col = i % POKELIST_PERCOL
  pokemon_loc = Loc.new(list_x(col), row >= POKELIST_SCROLL_ROWSTART ? list_y(POKELIST_SCROLL_ROWSTART - 1) : list_y(row))
  puts ">> row #{row}, col #{col} / #{pokemon_loc.x},#{pokemon_loc.y}"

  # Open Pokemon info screen
  adb_tap(pokemon_loc, 1)
  adb_verify_screenshot(SCREENSHOT_POKEMON_INFO)

  # Open appraisal screen and get to the part that shows the bars
  adb_tap(POKEMON_INFO_MENU_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_POKEMON_MENU)
  adb_tap(POKEMON_INFO_APPRAISE_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_POKEMON_APPRAISE_INITIAL)
  adb_tap(POKEMON_INFO_APPRAISE_DISMISS_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_POKEMON_APPRAISE_BARS)

  # Invoke Poke Genie to calculate percentage and copy the new Pokemon name to the clipboard
  adb_tap(POKEGENIE_LOC, DELAY_SLOW)
  adb_verify_screenshot(SCREENSHOT_POKEGENIE)

  # Dismiss Poke Genie and the appraisal screen
  adb_tap(POKEGENIE_DISMISS_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_POKEMON_APPRAISE_BARS)
  adb_tap(POKEMON_INFO_APPRAISE_DISMISS_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_POKEMON_INFO)

  # Open rename dialog
  adb_tap(POKEMON_INFO_RENAME_LOC, DELAY_NO_VERIFY)
  # adb_verify_screenshot(SCREENSHOT_RENAME)

  # Remove old name
  adb_key_repeat(KEYCODE_BACKSPACE, POKEMON_NAME_LENGTH, DELAY_NONE)

  # Paste new name
  adb_key(KEYCODE_PASTE, DELAY_NONE)

  # Dismiss keyboard
  adb_tap(POKEMON_INFO_RENAME_OK_LOC, DELAY_NO_VERIFY)

  # Rename Pokemon
  adb_tap(POKEMON_INFO_RENAME_OK_LOC, DELAY_VERIFY)
  adb_verify_screenshot(SCREENSHOT_POKEMON_INFO)

  # Close Pokemon info screen
  adb_tap(POKEMON_INFO_CLOSE_LOC, DELAY_VERIFY)
  adb_verify_screenshot(SCREENSHOT_POKELIST)

  # Scroll the Pokemon list by one row if needed
  if (row >= POKELIST_SCROLL_ROWSTART - 1 && col + 1 == POKELIST_PERCOL)
    # Trigger scroll & reset back to row before the end
    swipe_start = Loc.new(list_x(0), list_y(POKELIST_SCROLL_ROWSTART - 1))
    # this offset thing is because the fling scrolling isn't exact
    # so we alternate scrolling slightly too far and slightly not far enough
    swipe_end = Loc.new(swipe_start.x, swipe_start.y - (row_even ? POKELIST_SCROLL_DY_EVEN : POKELIST_SCROLL_DY_ODD))
    row_even = !row_even
    adb_swipe(swipe_start, swipe_end, POKELIST_SCROLL_DELAY, DELAY_SCROLL)
  end

  # look like a human
  sleep(rand())
end