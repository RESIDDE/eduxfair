// Building blocks shared by both consoles. Copied from
// consult-app/admin_dashboard/src/components/ui, which was itself written to
// mirror the Flutter widgets — so the student app and these consoles stay
// visually consistent without maintaining two design systems.
//
// The automotive-specific pieces (vehicle icons, the map Route widget) were
// dropped rather than carried over.
export { Alert } from './Alert';
export { Avatar } from './Avatar';
export { Button, GlassIconButton } from './Button';
export { Dialog } from './Dialog';
export { EmptyState, Loading } from './EmptyState';
export { Field, Input, Select, SearchField, Textarea } from './Field';
export { CardHeader, Eyebrow, SectionHeader, Toolbar } from './Headers';
export { KeyValueRow } from './KeyValueRow';
export { SegmentedControl } from './SegmentedControl';
export { HeroStats, SegmentProgressBar, StatsStrip } from './Stats';
export { Badge, StatusBadge } from './StatusBadge';
export { FlatChip, IconTile, SurfaceCard } from './SurfaceCard';
export { EmptyRow, TableCard, Td, Th, Tr } from './Table';
export { useSlidingIndicator } from './hooks';
