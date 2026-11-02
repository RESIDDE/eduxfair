import { useState } from 'react';
import { Plus, QrCode } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyRow,
  EmptyState,
  Field,
  Input,
  Loading,
  Select,
  SurfaceCard,
  TableCard,
  Td,
  Th,
  Toolbar,
  Tr,
} from '../../components/ui';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDate } from '../../lib/format';
import { countryName } from '../../lib/vocab';

/**
 * Fairs and their exhibitor booths.
 *
 * Booth codes are not secrets: a scan is authorized by the staff member's
 * membership of that institution, which `record_booth_visit()` checks. So a
 * code can be printed on a sign without creating a way in.
 */
export default function AdminFairsPage() {
  const [creatingFair, setCreatingFair] = useState(false);
  const [addingExhibitor, setAddingExhibitor] = useState(null);

  const { data: fairs, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('fairs')
        .select('*, fair_exhibitors(id, booth_code, booth_label, package, institutions(id, name, country))')
        .order('starts_at', { ascending: false }),
    [],
  );

  if (loading) return <Loading label="Loading fairs" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = fairs ?? [];

  return (
    <div className="flex flex-col gap-6 pb-4">
      <Toolbar summary={`${rows.length} fair${rows.length === 1 ? '' : 's'}`}>
        <Button icon={Plus} onClick={() => setCreatingFair(true)}>
          Create fair
        </Button>
      </Toolbar>

      {rows.length === 0 ? (
        <EmptyState
          icon={QrCode}
          title="No fairs yet"
          subtitle="Create one, add exhibitor booths, and students can register for a Fair Passport."
          action={
            <Button icon={Plus} onClick={() => setCreatingFair(true)}>
              Create fair
            </Button>
          }
        />
      ) : (
        rows.map((fair) => (
          <div key={fair.id} className="flex flex-col gap-3">
            <SurfaceCard className="p-5">
              <div className="flex items-start justify-between gap-4 flex-wrap">
                <div className="min-w-0">
                  <div className="flex items-center gap-2.5 flex-wrap">
                    <h2 className="font-bold text-[16px]">{fair.name}</h2>
                    {fair.is_active ? (
                      <Badge tone="success" compact>
                        Active
                      </Badge>
                    ) : (
                      <Badge tone="neutral" compact>
                        Archived
                      </Badge>
                    )}
                  </div>
                  <div className="mt-1 text-[13px] text-muted">
                    {[fair.venue, fair.city, countryName(fair.country)]
                      .filter(Boolean)
                      .join(', ')}{' '}
                    · {formatDate(fair.starts_at)} – {formatDate(fair.ends_at)}
                  </div>
                </div>
                <Button
                  size="sm"
                  icon={Plus}
                  variant="outline"
                  onClick={() => setAddingExhibitor(fair)}
                >
                  Add exhibitor
                </Button>
              </div>
            </SurfaceCard>

            <TableCard minWidth={660}>
              <thead>
                <tr>
                  <Th>Institution</Th>
                  <Th>Booth code</Th>
                  <Th>Label</Th>
                  <Th>Package</Th>
                </tr>
              </thead>
              <tbody>
                {(fair.fair_exhibitors ?? []).map((exhibitor) => (
                  <Tr key={exhibitor.id}>
                    <Td className="font-semibold">
                      {exhibitor.institutions?.name ?? '—'}
                    </Td>
                    <Td className="font-mono">{exhibitor.booth_code}</Td>
                    <Td>{exhibitor.booth_label ?? '—'}</Td>
                    <Td>{exhibitor.package.replace(/_/g, ' ')}</Td>
                  </Tr>
                ))}
                {(fair.fair_exhibitors ?? []).length === 0 && (
                  <EmptyRow colSpan={4}>No exhibitors yet</EmptyRow>
                )}
              </tbody>
            </TableCard>
          </div>
        ))
      )}

      {creatingFair && (
        <FairDialog
          onClose={() => setCreatingFair(false)}
          onSaved={() => {
            setCreatingFair(false);
            reload();
          }}
        />
      )}

      {addingExhibitor && (
        <ExhibitorDialog
          fair={addingExhibitor}
          onClose={() => setAddingExhibitor(null)}
          onSaved={() => {
            setAddingExhibitor(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function FairDialog({ onClose, onSaved }) {
  const [form, setForm] = useState({
    name: '',
    city: '',
    country: 'NG',
    venue: '',
    starts_at: '',
    ends_at: '',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const set = (key) => (event) =>
    setForm((prev) => ({ ...prev, [key]: event.target.value }));

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const slug = form.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '');

    const { error: writeError } = await supabase.from('fairs').insert({
      name: form.name.trim(),
      slug,
      city: form.city || null,
      country: form.country || null,
      venue: form.venue || null,
      starts_at: new Date(form.starts_at).toISOString(),
      ends_at: new Date(form.ends_at).toISOString(),
    });

    setBusy(false);

    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Create a fair"
      onClose={onClose}
      onSubmit={handleSubmit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            Create
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      <div className="flex flex-col gap-4">
        <Field label="Name">
          <Input
            value={form.name}
            onChange={set('name')}
            placeholder="Eduxfair International Education Fair — Lagos 2026"
            required
          />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="City">
            <Input value={form.city} onChange={set('city')} placeholder="Lagos" />
          </Field>
          <Field label="Country">
            <Select value={form.country} onChange={set('country')}>
              {['NG', 'GH', 'KE', 'ZA', 'CM', 'UG', 'TZ', 'RW'].map((code) => (
                <option key={code} value={code}>
                  {countryName(code)}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <Field label="Venue">
          <Input
            value={form.venue}
            onChange={set('venue')}
            placeholder="Eko Convention Centre, Victoria Island"
          />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Starts">
            <Input
              type="datetime-local"
              value={form.starts_at}
              onChange={set('starts_at')}
              required
            />
          </Field>
          <Field label="Ends">
            <Input
              type="datetime-local"
              value={form.ends_at}
              onChange={set('ends_at')}
              required
            />
          </Field>
        </div>
      </div>
    </Dialog>
  );
}

function ExhibitorDialog({ fair, onClose, onSaved }) {
  const [institutionId, setInstitutionId] = useState('');
  const [boothCode, setBoothCode] = useState('');
  const [boothLabel, setBoothLabel] = useState('');
  const [pkg, setPkg] = useState('booth_plus_platform');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const { data: institutions } = useQuery(
    (client) => client.from('institutions').select('id, name').order('name'),
    [],
  );

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const institution = (institutions ?? []).find((i) => i.id === institutionId);

    const { error: writeError } = await supabase.from('fair_exhibitors').insert({
      fair_id: fair.id,
      institution_id: institutionId,
      booth_code: boothCode.trim().toUpperCase(),
      booth_label: boothLabel || institution?.name || null,
      package: pkg,
    });

    setBusy(false);

    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Add an exhibitor"
      eyebrow={fair.name}
      onClose={onClose}
      onSubmit={handleSubmit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            Add
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      <div className="flex flex-col gap-4">
        <Field label="Institution">
          <Select
            value={institutionId}
            onChange={(e) => setInstitutionId(e.target.value)}
            required
          >
            <option value="">Choose…</option>
            {(institutions ?? []).map((institution) => (
              <option key={institution.id} value={institution.id}>
                {institution.name}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field
            label="Booth code"
            hint="Printed on the booth. Not a secret — staff still have to be signed in."
          >
            <Input
              value={boothCode}
              onChange={(e) => setBoothCode(e.target.value.toUpperCase())}
              placeholder="A01"
              required
              className="font-mono"
            />
          </Field>
          <Field label="Package">
            <Select value={pkg} onChange={(e) => setPkg(e.target.value)}>
              <option value="booth_only">Booth only</option>
              <option value="booth_plus_platform">Booth + platform</option>
              <option value="sponsor">Sponsor</option>
            </Select>
          </Field>
        </div>
        <Field label="Booth label" hint="Defaults to the institution name.">
          <Input value={boothLabel} onChange={(e) => setBoothLabel(e.target.value)} />
        </Field>
      </div>
    </Dialog>
  );
}
