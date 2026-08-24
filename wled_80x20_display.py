"""Compact MQTT information display for an 80x20 WLED matrix."""

from __future__ import annotations

import json
import signal
import threading
import time
from dataclasses import dataclass
from typing import Any

import paho.mqtt.client as mqtt
import requests


WLED_STATE_URL = "http://192.168.178.218/json/state"
HOUSE_MQTT_HOST = "192.168.178.41"
VENUS_MQTT_HOST = "192.168.178.57"
MQTT_PORT = 1883
PAGE_SECONDS = 10


@dataclass
class DisplayValues:
    outside_temperature: float | None = None
    hot_water_temperature: float | None = None
    hot_water_power: float | None = None
    heat_pump_on: bool | None = None
    heat_pump_power: float | None = None
    heat_pump_outlet: float | None = None
    battery_soc: float | None = None
    battery_current: float | None = None
    grid_power: float | None = None
    pv_growatt: float = 0.0
    pv_mppt_0: float = 0.0
    pv_mppt_1: float = 0.0


values = DisplayValues()
values_lock = threading.Lock()
stop_event = threading.Event()


def mqtt_client(client_id: str) -> mqtt.Client:
    """Create a client that works with both paho-mqtt 1.x and 2.x."""
    try:
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, client_id=client_id)
    except AttributeError:
        return mqtt.Client(client_id=client_id)


def json_value(payload: bytes) -> float | None:
    """Read a Victron {\"value\": ...} MQTT payload."""
    try:
        value = json.loads(payload.decode("utf-8")).get("value")
        return None if value is None else float(value)
    except (UnicodeDecodeError, ValueError, TypeError, AttributeError):
        return None


def plain_number(payload: bytes) -> float | None:
    try:
        return float(payload.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return None


def on_venus_message(client: mqtt.Client, userdata: Any, message: mqtt.MQTTMessage) -> None:
    value = json_value(message.payload)
    if value is None:
        return

    with values_lock:
        if message.topic.endswith("/Dc/Battery/Soc"):
            values.battery_soc = value
        elif message.topic.endswith("/Dc/Battery/Current"):
            values.battery_current = value
        elif message.topic.endswith("/grid/40/Ac/Power"):
            values.grid_power = value
        elif message.topic.endswith("/pvinverter/41/Ac/Power"):
            values.pv_growatt = value
        elif message.topic.endswith("/solarcharger/274/Pv/0/P"):
            values.pv_mppt_0 = value
        elif message.topic.endswith("/solarcharger/274/Pv/1/P"):
            values.pv_mppt_1 = value


def update_temperature_sensors(payload: bytes) -> None:
    try:
        data = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return

    with values_lock:
        for sensor in data.values():
            if not isinstance(sensor, dict):
                continue
            sensor_id = str(sensor.get("Id", "")).upper()
            temperature = sensor.get("Temperature")
            if temperature is None:
                continue
            if sensor_id == "00000132F2CB":
                values.outside_temperature = float(temperature)
            elif sensor_id == "00000609DB72":
                values.hot_water_temperature = float(temperature)


def on_house_message(client: mqtt.Client, userdata: Any, message: mqtt.MQTTMessage) -> None:
    if message.topic in ("tele/warmwasser/SENSOR", "tele/tasmota_esp32c3_heizung/SENSOR"):
        update_temperature_sensors(message.payload)
        return

    with values_lock:
        if message.topic == "jeisha/main/Heatpump_State":
            value = plain_number(message.payload)
            if value is not None:
                values.heat_pump_on = value != 0
        elif message.topic == "jeisha/main/Heat_Power_Consumption":
            values.heat_pump_power = plain_number(message.payload)
        elif message.topic == "jeisha/main/Main_Outlet_Temp":
            values.heat_pump_outlet = plain_number(message.payload)
        elif message.topic == "tele/brauchwasser_wp/SENSOR":
            try:
                data = json.loads(message.payload.decode("utf-8"))
                power = data.get("ENERGY", {}).get("Power")
                values.hot_water_power = None if power is None else float(power)
            except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
                pass


def text(value: float | None, decimals: int = 0, missing: str = "--") -> str:
    if value is None:
        return missing
    return f"{value:.{decimals}f}"


def cell_segment(
    segment_id: int,
    column: int,
    row: int,
    label: str,
    color: tuple[int, int, int],
) -> dict[str, Any]:
    """Build one cell in the two-column by three-row display grid."""
    start_x = column * 40
    start_y = row * 7
    return {
        "id": segment_id,
        "start": start_x,
        "stop": start_x + 40,
        "startY": start_y,
        "stopY": start_y + 6,
        "fx": 122,
        "n": label[:32],
        "sx": 225,
        "ix": 128,
        "c1": 0,
        "c2": 0,
        "pal": 0,
        "col": [list(color), [0, 0, 0], [0, 0, 0]],
    }


def send_page(cells: list[tuple[str, tuple[int, int, int]]]) -> None:
    segments = [
        cell_segment(index, index % 2, index // 2, label, color)
        for index, (label, color) in enumerate(cells)
    ]
    body = {
        "on": True,
        "bri": 72,
        "transition": 0,
        "mainseg": 0,
        "seg": segments,
    }
    response = requests.post(WLED_STATE_URL, json=body, timeout=5)
    response.raise_for_status()


def pages() -> list[list[tuple[str, tuple[int, int, int]]]]:
    with values_lock:
        pv_power = values.pv_growatt + values.pv_mppt_0 + values.pv_mppt_1
        wp_state = "EIN" if values.heat_pump_on else "AUS" if values.heat_pump_on is not None else "--"
        battery_color = (0, 220, 80) if (values.battery_current or 0) >= 0 else (255, 60, 0)
        grid_color = (0, 220, 80) if (values.grid_power or 0) < 0 else (255, 170, 0)

        return [
            [
                ("#HHMM0", (255, 255, 255)),
                ("#DDMM0", (100, 160, 255)),
                (f"PV{text(pv_power)}W", (255, 190, 0)),
                (f"N{text(values.grid_power)}W", grid_color),
                (f"B{text(values.battery_soc, 0)}%", battery_color),
                (f"I{text(values.battery_current, 1)}A", battery_color),
            ],
            [
                (f"A{text(values.outside_temperature, 1)}C", (0, 150, 255)),
                (f"WW{text(values.hot_water_temperature, 1)}C", (255, 120, 0)),
                (f"WP {wp_state}", (180, 80, 255) if wp_state == "EIN" else (100, 100, 100)),
                (f"WP{text(values.heat_pump_power)}W", (180, 80, 255)),
                (f"VL{text(values.heat_pump_outlet, 1)}C", (255, 80, 120)),
                (f"BWW{text(values.hot_water_power)}W", (255, 160, 80)),
            ],
        ]


def connect_clients() -> list[mqtt.Client]:
    house = mqtt_client("wled-display-house")
    house.on_message = on_house_message
    house.connect(HOUSE_MQTT_HOST, MQTT_PORT, 60)
    for topic in (
        "tele/warmwasser/SENSOR",
        "tele/tasmota_esp32c3_heizung/SENSOR",
        "tele/brauchwasser_wp/SENSOR",
        "jeisha/main/Heatpump_State",
        "jeisha/main/Heat_Power_Consumption",
        "jeisha/main/Main_Outlet_Temp",
    ):
        house.subscribe(topic)
    house.loop_start()

    venus = mqtt_client("wled-display-venus")
    venus.on_message = on_venus_message
    venus.connect(VENUS_MQTT_HOST, MQTT_PORT, 60)
    for topic in (
        "N/c0619ab0909d/system/0/Dc/Battery/Soc",
        "N/c0619ab0909d/system/0/Dc/Battery/Current",
        "N/c0619ab0909d/grid/40/Ac/Power",
        "N/c0619ab0909d/pvinverter/41/Ac/Power",
        "N/c0619ab0909d/solarcharger/274/Pv/0/P",
        "N/c0619ab0909d/solarcharger/274/Pv/1/P",
    ):
        venus.subscribe(topic)
    venus.loop_start()
    return [house, venus]


def stop(signum: int, frame: Any) -> None:
    stop_event.set()


def main() -> None:
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    clients = connect_clients()
    print("80x20 MQTT display started; stop with Ctrl+C")

    try:
        while not stop_event.is_set():
            for page in pages():
                if stop_event.is_set():
                    break
                try:
                    send_page(page)
                except requests.RequestException as error:
                    print(f"WLED request failed: {error}")
                stop_event.wait(PAGE_SECONDS)
    finally:
        for client in clients:
            client.loop_stop()
            client.disconnect()


if __name__ == "__main__":
    main()
