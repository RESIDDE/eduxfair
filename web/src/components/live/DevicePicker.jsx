import { useEffect, useState } from 'react';
import { Room } from 'livekit-client';
import { Field, Select } from '../ui';

const KINDS = [
  { kind: 'audioinput', label: 'Microphone' },
  { kind: 'videoinput', label: 'Camera' },
  { kind: 'audiooutput', label: 'Speaker' },
];

/**
 * Device switching, live.
 *
 * Labels are blank until a permission has been granted at least once, which is
 * a browser rule rather than something to work around — so an unlabelled entry
 * falls back to a short form of its id rather than rendering an empty option.
 */
export function DevicePicker({ actions }) {
  const [devices, setDevices] = useState([]);
  const [selected, setSelected] = useState({});

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const found = await Room.getLocalDevices();
        if (active) setDevices(found);
      } catch {
        if (active) setDevices([]);
      }
    };
    load();
    navigator.mediaDevices?.addEventListener?.('devicechange', load);
    return () => {
      active = false;
      navigator.mediaDevices?.removeEventListener?.('devicechange', load);
    };
  }, []);

  return (
    <div className="flex flex-col gap-4 p-4">
      {KINDS.map(({ kind, label }) => {
        const options = devices.filter((d) => d.kind === kind);
        return (
          <Field key={kind} label={label}>
            <Select
              value={selected[kind] ?? ''}
              onChange={async (e) => {
                const id = e.target.value;
                setSelected((prev) => ({ ...prev, [kind]: id }));
                await actions.switchDevice(kind, id);
              }}
            >
              <option value="">System default</option>
              {options.map((d) => (
                <option key={d.deviceId} value={d.deviceId}>
                  {d.label || `${label} ${d.deviceId.slice(0, 6)}`}
                </option>
              ))}
            </Select>
          </Field>
        );
      })}
      {devices.length === 0 && (
        <p className="text-[12px] text-subtle">
          No devices listed yet. Allow the camera and microphone and they will appear.
        </p>
      )}
    </div>
  );
}
