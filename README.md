# Loud Numbers - The Carrington Event

This is a [data sonification](https://www.loudnumbers.net/sonification) script for Norns. It turns .csv data from the Carrington Event into control voltages.

## Requirements

Monome Norns or Norns Shield
Optional: Grid, Crow

## Instructions

Place data files in the we/data/loudnumbers_norns/csv folder - the same folder as_temperatures.csv. Once you've loaded your file, restart the script and select it through the parameters menu.

- ENC 3: select duration
- KEY 3: toggle play/pause
- KEY 2: reset and stop

## Crow support

- OUT3 = data value scaled to -5V-5V
- OUT4 = data value scaled to 0V-10V

## Changelog

### v0.1

- First release
- Fork from the [Loud Numbers](https://github.com/duncangeere/loudnumbers_norns) script.

## Loud Numbers?

It's the name of my [data sonification studio](https://www.loudnumbers.net/). Worth checking out if you want to see what's possible with sonification.
