package Sfams::Schema::Result::Sample;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

Sfams::Schema::Result::Sample

=cut

__PACKAGE__->table("samples");

=head1 ACCESSORS

=head2 sample_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 project_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 sample_alt_id

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 country

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 gender

  data_type: 'varchar'
  is_nullable: 1
  size: 64

=head2 age

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 1

=head2 bmi

  data_type: 'decimal'
  is_nullable: 1
  size: [5,2]

=head2 ibd

  data_type: 'tinyint'
  is_nullable: 1

=head2 crohn_disease

  data_type: 'tinyint'
  is_nullable: 1

=head2 ulcerative_colitis

  data_type: 'tinyint'
  is_nullable: 1

=head2 location

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 datesampled

  data_type: 'varchar'
  is_nullable: 1
  size: 25

=head2 site_id

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 region

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 depth

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 water_depth

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 salinity

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 temperature

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 volume_filtered

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 chlorophyll_density

  data_type: 'varchar'
  is_nullable: 1
  size: 512

=head2 annual_chlorophyll_density

  data_type: 'varchar'
  is_nullable: 1
  size: 512

=head2 other_metadata

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "sample_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "project_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "sample_alt_id",
  { data_type => "varchar", is_nullable => 0, size => 256 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "country",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "gender",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "age",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 1 },
  "bmi",
  { data_type => "decimal", is_nullable => 1, size => [5, 2] },
  "ibd",
  { data_type => "tinyint", is_nullable => 1 },
  "crohn_disease",
  { data_type => "tinyint", is_nullable => 1 },
  "ulcerative_colitis",
  { data_type => "tinyint", is_nullable => 1 },
  "location",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "datesampled",
  { data_type => "varchar", is_nullable => 1, size => 25 },
  "site_id",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "region",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "depth",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "water_depth",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "salinity",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "temperature",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "volume_filtered",
  { data_type => "varchar", is_nullable => 1, size => 256 },
  "chlorophyll_density",
  { data_type => "varchar", is_nullable => 1, size => 512 },
  "annual_chlorophyll_density",
  { data_type => "varchar", is_nullable => 1, size => 512 },
  "other_metadata",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("sample_id");
__PACKAGE__->add_unique_constraint("project_id_sample_alt_id", ["project_id", "sample_alt_id"]);
__PACKAGE__->add_unique_constraint("sample_alt_id", ["sample_alt_id"]);

=head1 RELATIONS

=head2 metareads

Type: has_many

Related object: L<Sfams::Schema::Result::Metaread>

=cut

__PACKAGE__->has_many(
  "metareads",
  "Sfams::Schema::Result::Metaread",
  { "foreign.sample_id" => "self.sample_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 orfs

Type: has_many

Related object: L<Sfams::Schema::Result::Orf>

=cut

__PACKAGE__->has_many(
  "orfs",
  "Sfams::Schema::Result::Orf",
  { "foreign.sample_id" => "self.sample_id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 project

Type: belongs_to

Related object: L<Sfams::Schema::Result::Project>

=cut

__PACKAGE__->belongs_to(
  "project",
  "Sfams::Schema::Result::Project",
  { project_id => "project_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "CASCADE",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-09-05 10:57:15
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:YIC2yKlNdrVFrUU6GMc9Ng


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
