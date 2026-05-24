<?php

namespace App\Controller\Admin\Base;

use EasyCorp\Bundle\EasyAdminBundle\Config\Crud;
use EasyCorp\Bundle\EasyAdminBundle\Config\Filters;
use EasyCorp\Bundle\EasyAdminBundle\Config\Action;
use EasyCorp\Bundle\EasyAdminBundle\Config\Actions;
use EasyCorp\Bundle\EasyAdminBundle\Config\Assets;
use EasyCorp\Bundle\EasyAdminBundle\Controller\AbstractCrudController;
use EasyCorp\Bundle\EasyAdminBundle\Field\IdField;
use EasyCorp\Bundle\EasyAdminBundle\Field\DateTimeField;
use EasyCorp\Bundle\EasyAdminBundle\Field\BooleanField;
use EasyCorp\Bundle\EasyAdminBundle\Field\AssociationField;
use EasyCorp\Bundle\EasyAdminBundle\Field\TextField;
use EasyCorp\Bundle\EasyAdminBundle\Field\TextareaField;
use EasyCorp\Bundle\EasyAdminBundle\Field\IntegerField;
use EasyCorp\Bundle\EasyAdminBundle\Field\NumberField;
use EasyCorp\Bundle\EasyAdminBundle\Field\DateField;
use EasyCorp\Bundle\EasyAdminBundle\Field\TimeField;
use EasyCorp\Bundle\EasyAdminBundle\Field\UrlField;
use EasyCorp\Bundle\EasyAdminBundle\Field\EmailField;
use EasyCorp\Bundle\EasyAdminBundle\Field\ArrayField;
use Vich\UploaderBundle\Form\Type\VichFileType;
use Vich\UploaderBundle\Form\Type\VichImageType;
use EasyCorp\Bundle\EasyAdminBundle\Config\KeyValueStore;
use EasyCorp\Bundle\EasyAdminBundle\Field\Field;
use EasyCorp\Bundle\EasyAdminBundle\Contracts\Field\FieldInterface;
use App\Filter\CaseInsensitiveTextFilter;
use Doctrine\ORM\EntityManagerInterface;

abstract class BaseCrudController extends AbstractCrudController
{
    public const AUDIT_FIELDS = [
        'creadoEl', 'creEl', 'creadoPor', 'crePor', 'modificadoEl', 'modEl', 'modificadoPor', 'modPor',
        'resultadoEvaluacionIa', 'activo', 'esActivo', 'estado'
    ];

    public const INDEX_EXCLUDES = [];
    public const INDEX_INCLUDES = [];
    public const DETAIL_EXCLUDES = [];
    public const FORM_EXCLUDES = [];
    public const FORM_INCLUDES = [];
    public const FIELDS_ORDER = [];
    public const ENTITY = null;
    public const RELATION_CONFIG = [];

    public function configureCrud(Crud $crud): Crud
    {
        try {
            $reflection = new \ReflectionClass(static::class);
            if ($reflection->hasConstant('ENTITY')) {
                $entityLabels = $reflection->getConstant('ENTITY');
                if (is_array($entityLabels)) {
                    if (isset($entityLabels[0])) $crud->setEntityLabelInSingular($entityLabels[0]);
                    if (isset($entityLabels[1])) $crud->setEntityLabelInPlural($entityLabels[1]);
                }
            }
        } catch (\Exception $e) {}

        return $crud
            ->renderContentMaximized()
            ->setDefaultSort(['id' => 'DESC'])
            ->setPageTitle('index', 'Listado de %entity_label_plural%')
            ->setPageTitle('new', 'Registrar %entity_label_singular%')
            ->setPageTitle('edit', 'Editar %entity_label_singular%')
            ->setPageTitle('detail', 'Detalle de %entity_label_singular%')
            ->setPaginatorPageSize(18)
            ->setSearchFields($this->getAutoSearchFields())
            ->overrideTemplate('crud/detail', 'Admin/common/layout_detail.html.twig')
        ;
    }

    protected function getAutoSearchFields(): array
    {
        $searchFields = ['id'];

        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return $searchFields;

            $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());

            foreach ($metadata->fieldMappings as $fieldName => $mapping) {
                if ($this->isAuditField($fieldName) || $this->isExcludedFromIndex($fieldName)) continue;
                if (in_array($mapping['type'], ['string', 'text', 'integer', 'decimal'])) {
                    $searchFields[] = $fieldName;
                }
            }

            foreach ($metadata->associationMappings as $assocName => $mapping) {
                if ($mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY) continue;
                if ($this->isAuditField($assocName) || $this->isExcludedFromIndex($assocName)) continue;

                $searchFields[] = $assocName . '.id';
                $targetMetadata = $entityManager->getClassMetadata($mapping['targetEntity']);
                if ($targetMetadata->hasField('nombre')) $searchFields[] = $assocName . '.nombre';
                if ($targetMetadata->hasField('paterno')) $searchFields[] = $assocName . '.paterno';
                if ($targetMetadata->hasField('sigla')) $searchFields[] = $assocName . '.sigla';
            }
        } catch (\Exception $e) {}

        return array_unique($searchFields);
    }

    public static function getEntityFqcn(): string
    {
        $controllerClass = get_called_class();
        $entityName = str_replace('CrudController', '', (new \ReflectionClass($controllerClass))->getShortName());

        $namespaces = ['App\\Entity\\'];

        foreach ($namespaces as $ns) {
            $fullClass = $ns . $entityName;
            if (class_exists($fullClass)) {
                return $fullClass;
            }
        }

        throw new \Exception("No se pudo autodetectar la entidad para $controllerClass. Por favor, defina getEntityFqcn() manualmente.");
    }

    protected function getFieldsOrder(): array
    {
        if (!empty(static::FIELDS_ORDER)) return static::FIELDS_ORDER;
        return static::INDEX_INCLUDES;
    }

    public function configureActions(Actions $actions): Actions
    {
        return $actions
            ->add(Crud::PAGE_INDEX, Action::DETAIL)
            ->reorder(Crud::PAGE_INDEX, [Action::DETAIL, Action::EDIT, Action::DELETE])
            ->setPermission(Action::DETAIL, 'ROLE_USER')
        ;
    }

    public function configureResponseParameters(KeyValueStore $responseParameters): KeyValueStore
    {
        if (Crud::PAGE_DETAIL === $responseParameters->get('pageName')) {
            $responseParameters->set('campos_excluidos', $this->getCamposExcluidosDetalle());
        }
        return $responseParameters;
    }

    public function configureFilters(Filters $filters): Filters
    {
        return $this->applyFilters($filters);
    }

    protected function applyFilters(Filters $filters, array $additionalFilters = []): Filters
    {
        if (!$this->shouldShowFilters()) return $filters;

        $filters->add('id');
        if ($this->hasField('nombre')) $filters->add(CaseInsensitiveTextFilter::new('nombre'));
        if ($this->hasField('activo')) $filters->add('activo');
        if ($this->hasField('creadoEl')) $filters->add('creadoEl');

        foreach ($additionalFilters as $filter) {
            if (is_string($filter)) {
                if ($this->isTextField($filter)) $filters->add(CaseInsensitiveTextFilter::new($filter));
                else $filters->add($filter);
            } else {
                $filters->add($filter);
            }
        }

        return $filters;
    }

    protected function isTextField(string $propertyName): bool
    {
        try {
            $reflection = new \ReflectionClass($this->getEntityFqcn());
            if (!$reflection->hasProperty($propertyName)) return false;
            $property = $reflection->getProperty($propertyName);
            $type = $property->getType();
            if (!$type) return false;
            return $type->getName() === 'string';
        } catch (\Exception $e) { return false; }
    }

    protected function shouldShowFilters(): bool
    {
        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return true;
            $count = $entityManager->getRepository($this->getEntityFqcn())->count([]);
            return $count > 20;
        } catch (\Exception $e) { return true; }
    }

    protected function isDeprecated(string $fieldName): bool
    {
        try {
            $reflection = new \ReflectionProperty($this->getEntityFqcn(), $fieldName);
            $docComment = $reflection->getDocComment();
            return $docComment && str_contains($docComment, '@deprecated');
        } catch (\Exception $e) { return false; }
    }

    public function configureFields(string $pageName): iterable
    {
        $fields = iterator_to_array($this->getAutoFields($pageName));
        $order = $this->getFieldsOrder();

        $priorityHead = ['id', 'creadoEl', 'creEl', 'creadoPor', 'crePor', 'empleado'];
        $orderedFields = [];
        $addedProperties = [];

        foreach ($priorityHead as $prop) {
            if (!in_array($prop, $order)) {
                foreach ($fields as $field) {
                    if ($field->getAsDto()->getProperty() === $prop) {
                        $orderedFields[] = $field;
                        $addedProperties[] = $prop;
                        break;
                    }
                }
            }
        }

        foreach ($order as $fieldName) {
            foreach ($fields as $field) {
                if ($field->getAsDto()->getProperty() === $fieldName) {
                    $orderedFields[] = $field;
                    $addedProperties[] = $fieldName;
                    break;
                }
            }
        }

        foreach ($fields as $field) {
            $property = $field->getAsDto()->getProperty();
            if (!in_array($property, $addedProperties)) {
                $orderedFields[] = $field;
            }
        }

        return $orderedFields;
    }

    protected function isAuditField(string $fieldName): bool
    {
        if (in_array($fieldName, self::AUDIT_FIELDS)) return true;
        return (bool) preg_match('/(Anular|Cambios|Pin|Revision)$/i', $fieldName);
    }

    protected function isExcludedFromIndex(string $fieldName): bool
    {
        $essentialFields = ['id', 'empleado', 'creadoEl', 'creEl', 'creadoPor', 'crePor'];
        if (in_array($fieldName, $essentialFields)) return false;

        if (!empty(static::INDEX_INCLUDES)) {
            return !in_array($fieldName, $this->getFieldsOrder());
        }

        if (in_array($fieldName, static::INDEX_EXCLUDES)) return true;
        return (bool) preg_match('/(Cambios|Anular|Pin|Revision|Observacion|password)$/i', $fieldName);
    }

    protected function isExcludedFromForm(string $fieldName, string $pageName): bool
    {
        if ($pageName !== Crud::PAGE_NEW && $pageName !== Crud::PAGE_EDIT) return false;

        if (!empty(static::FORM_INCLUDES)) {
            return !in_array($fieldName, static::FORM_INCLUDES);
        }

        return in_array($fieldName, static::FORM_EXCLUDES);
    }

    protected function getLabel(string $fieldName, string $pageName): ?string
    {
        $preferShort = ($pageName === Crud::PAGE_INDEX);

        if ($preferShort) {
            if ($fieldName === 'creadoPor' || $fieldName === 'crePor') return 'CPor';
            if ($fieldName === 'modificadoPor' || $fieldName === 'modPor') return 'MPor';
            if ($fieldName === 'creadoEl' || $fieldName === 'creEl') return 'Fecha Creación';
            if ($fieldName === 'nomArchivo') return 'Doc.Aut.';
        } else {
            if ($fieldName === 'creadoPor' || $fieldName === 'crePor') return 'Creado Por';
            if ($fieldName === 'modificadoPor' || $fieldName === 'modPor') return 'Modificado Por';
            if ($fieldName === 'creadoEl' || $fieldName === 'creEl') return 'Fecha Creación';
            if ($fieldName === 'nomArchivo') return 'Doc. Autorizando';
        }

        try {
            $entityFqcn = static::getEntityFqcn();
            $reflection = new \ReflectionClass($entityFqcn);

            $prop = null;
            $currentClass = $reflection;
            while ($currentClass) {
                if ($currentClass->hasProperty($fieldName)) {
                    $prop = $currentClass->getProperty($fieldName);
                    break;
                }
                $currentClass = $currentClass->getParentClass();
            }

            if ($prop) {
                foreach ($prop->getAttributes() as $attr) {
                    if (str_contains($attr->getName(), 'AdminLabel')) {
                        $adminLabel = $attr->newInstance();
                        if ($preferShort && $adminLabel->short) return $adminLabel->short;
                        return $adminLabel->full;
                    }
                }
            }
        } catch (\Exception $e) {}

        return null;
    }

    protected function getHelpText(string $fieldName): ?string
    {
        try {
            $entityFqcn = static::getEntityFqcn();
            $reflection = new \ReflectionClass($entityFqcn);

            $prop = null;
            $currentClass = $reflection;
            while ($currentClass) {
                if ($currentClass->hasProperty($fieldName)) {
                    $prop = $currentClass->getProperty($fieldName);
                    break;
                }
                $currentClass = $currentClass->getParentClass();
            }

            if (!$prop) return null;

            foreach ($prop->getAttributes() as $attr) {
                if (str_contains($attr->getName(), 'AdminLabel')) {
                    $memo = $attr->newInstance()->memo;
                    if ($memo) return $memo;
                    break;
                }
            }

            foreach ($prop->getAttributes() as $attr) {
                $name = $attr->getName();
                if (str_contains($name, 'Constraints\File') || str_contains($name, 'Constraints\Image')) {
                    $args = $attr->getArguments();
                    if (isset($args['mimeTypesMessage'])) return $args['mimeTypesMessage'];

                    $mimeTypes = $args['mimeTypes'] ?? $args[0] ?? [];
                    if (is_string($mimeTypes)) $mimeTypes = [$mimeTypes];

                    if (!empty($mimeTypes) && is_array($mimeTypes)) {
                        $extensions = [];
                        foreach ($mimeTypes as $mime) {
                            if (!is_string($mime)) continue;
                            if ($mime === 'application/pdf') $extensions[] = 'PDF';
                            elseif (str_contains($mime, 'image/jpeg')) $extensions[] = 'JPG';
                            elseif (str_contains($mime, 'image/png')) $extensions[] = 'PNG';
                            elseif (str_contains($mime, 'image/gif')) $extensions[] = 'GIF';
                        }
                        if (!empty($extensions)) return 'Solo archivos: ' . implode(', ', array_unique($extensions));
                    }
                }
            }
        } catch (\Exception $e) {}

        return null;
    }

    protected function getAutoFields(string $pageName, array $excluded = []): iterable
    {
        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return;

            $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());
            $vichMappings = $this->getVichMappings();
            $vichFileProperties = array_keys($vichMappings);
            $vichNameProperties = array_values($vichMappings);

            $allExcludes = array_merge($excluded, ['id', 'password', 'observacion', 'observaciones']);

            if ($pageName === Crud::PAGE_DETAIL) {
                $allExcludes = array_merge($allExcludes, static::AUDIT_FIELDS, static::DETAIL_EXCLUDES, $this->getCamposExcluidosDetalle());
            }

            if (!in_array('id', $excluded)) {
                yield IdField::new('id', 'ID')->onlyOnIndex();
            }

            $priorityFields = ['empleado', 'creadoEl', 'creEl', 'creadoPor', 'crePor'];
            foreach ($priorityFields as $pField) {
                if (!in_array($pField, $excluded) && !$this->isExcludedFromIndex($pField) && $this->hasField($pField)) {
                    $label = $this->getLabel($pField, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $pField));
                    $assocMetadata = $metadata->associationMappings[$pField] ?? null;

                    if ($assocMetadata) {
                        $required = !($assocMetadata['joinColumns'][0]['nullable'] ?? true);
                        $field = $this->createAssociationField($pField, $label, $required, 6, $pageName);
                    } else {
                        $mapping = $metadata->fieldMappings[$pField];
                        $field = $this->createFieldByType($pField, $mapping['type'], $pageName)
                            ->setLabel($label)
                            ->setRequired(!($mapping['nullable'] ?? true));
                    }

                    if ($field) {
                        if ($this->isAuditField($pField)) $field->hideOnForm();
                        if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($pField, $pageName)) $field->hideOnForm();
                        $allExcludes[] = $pField;
                        yield $field;
                    }
                }
            }

            foreach ($metadata->fieldMappings as $fieldName => $mapping) {
                if (in_array($fieldName, $allExcludes) || in_array($fieldName, $vichFileProperties) || in_array($fieldName, $vichNameProperties) || $this->isDeprecated($fieldName)) continue;
                if ($pageName === Crud::PAGE_INDEX && $this->isExcludedFromIndex($fieldName)) continue;
                if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($fieldName, $pageName)) continue;

                $required = !($mapping['nullable'] ?? true);
                $field = $this->createFieldByType($fieldName, $mapping['type'], $pageName)->setRequired($required);
                if ($this->isAuditField($fieldName)) $field->hideOnForm();
                yield $field;
            }

            foreach ($metadata->associationMappings as $assocName => $mapping) {
                if (in_array($assocName, $allExcludes) || $this->isDeprecated($assocName)) continue;
                if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($assocName, $pageName)) continue;

                $isToMany = $mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY;

                if ($isToMany && isset($mapping['mappedBy']) && $this->isAuditField($mapping['mappedBy'])) continue;

                if ($pageName === Crud::PAGE_INDEX) {
                    if ($isToMany) continue;
                    if ($this->isExcludedFromIndex($assocName)) continue;

                    $label = $this->getLabel($assocName, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $assocName));
                    yield AssociationField::new($assocName, $label)
                        ->setTemplatePath('Admin/field/text_plain.html.twig')
                        ->formatValue(function ($value) use ($assocName) {
                            if (null === $value) return '';
                            if (is_object($value)) {
                                if (method_exists($value, 'getSigla')) return $value->getSigla();
                                if (preg_match('/(creadoPor|crePor|modificadoPor|modPor)$/i', $assocName)) {
                                    if (method_exists($value, 'getIniciales')) return $value->getIniciales();
                                }
                                if (method_exists($value, '__toString')) return (string) $value;
                                if (method_exists($value, 'getNombre')) return $value->getNombre();
                                if (method_exists($value, 'getId')) return '#' . $value->getId();
                                return (new \ReflectionClass($value))->getShortName();
                            }
                            return (string) $value;
                        });
                } else {
                    $required = !($mapping['joinColumns'][0]['nullable'] ?? true);
                    $field = $this->createAssociationField($assocName, ucfirst($assocName), $required, 6, $pageName);
                    if ($this->isAuditField($assocName)) $field->hideOnForm();
                    $isInverse = isset($mapping['mappedBy']);
                    if ($isToMany || $isInverse) {
                        $field->hideOnDetail();
                        $field->hideOnForm();
                    }
                    yield $field;
                }
            }

            foreach ($vichMappings as $fileField => $nameField) {
                if (in_array($fileField, $allExcludes) || in_array($nameField, $allExcludes)) continue;

                $label = $this->getLabel($nameField, $pageName)
                    ?? $this->getLabel($fileField, $pageName)
                    ?? ucfirst(preg_replace('/File$/', '', $fileField));

                if ($pageName !== Crud::PAGE_INDEX && $pageName !== Crud::PAGE_DETAIL) {
                    if ($this->isExcludedFromForm($fileField, $pageName)) continue;
                    $formField = Field::new($fileField, $label)->setColumns(6);
                    if (preg_match('/(foto|imagen|img|photo|image)/i', $fileField)) {
                        $formField->setFormType(VichImageType::class);
                    } else {
                        $formField->setFormType(VichFileType::class);
                    }
                    if ($help = ($this->getHelpText($nameField) ?? $this->getHelpText($fileField))) {
                        $formField->setHelp($help);
                        $formField->setFormTypeOption('help', $help);
                    }
                    yield $formField;
                }

                yield $this->createImageField($nameField, $label, $this->getUploadUrl(), $pageName)->hideOnForm();
            }

            foreach (['observacion', 'observaciones'] as $obsField) {
                if (!$this->hasField($obsField)) continue;
                if ($this->isExcludedFromForm($obsField, $pageName)) continue;
                yield $this->createTextareaField($obsField, ucfirst($obsField), true, 12);
            }

        } catch (\Exception $e) {}
    }

    protected function createFieldByType(string $propertyName, string $doctrineType, string $pageName): FieldInterface
    {
        $label = $this->getLabel($propertyName, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $propertyName));

        $field = match ($doctrineType) {
            'integer', 'smallint', 'bigint' => IntegerField::new($propertyName, $label),
            'decimal', 'float'              => NumberField::new($propertyName, $label),
            'boolean'                       => BooleanField::new($propertyName, $label)->renderAsSwitch($pageName !== Crud::PAGE_INDEX),
            'datetime', 'datetimetz'        => DateTimeField::new($propertyName, $label)->setFormat('dd/MM/yyyy HH:mm'),
            'date'                          => DateField::new($propertyName, $label)->setFormat('dd/MM/yyyy'),
            'time'                          => TimeField::new($propertyName, $label),
            'text'                          => TextareaField::new($propertyName, $label)->hideOnIndex(),
            'array', 'json'                 => ArrayField::new($propertyName, $label),
            'string'                        => $this->guessStringField($propertyName, $label),
            default                         => TextField::new($propertyName, $label),
        };

        if ($pageName !== Crud::PAGE_INDEX) {
            if ($help = $this->getHelpText($propertyName)) $field->setHelp($help);
        }

        return $field->setColumns(6);
    }

    protected function guessStringField(string $propertyName, string $label): FieldInterface
    {
        if (str_contains(strtolower($propertyName), 'email')) return EmailField::new($propertyName, $label);
        if (str_contains(strtolower($propertyName), 'url') || str_contains(strtolower($propertyName), 'web')) return UrlField::new($propertyName, $label);
        if (preg_match('/(descripcion|comentario|nota|detalle)/i', $propertyName)) return TextareaField::new($propertyName, $label)->hideOnIndex();
        return TextField::new($propertyName, $label);
    }

    protected function getVichMappings(): array
    {
        $mappings = [];
        try {
            $reflection = new \ReflectionClass(static::getEntityFqcn());
            $currentClass = $reflection;
            while ($currentClass) {
                foreach ($currentClass->getProperties() as $prop) {
                    if (isset($mappings[$prop->getName()])) continue;
                    foreach ($prop->getAttributes() as $attr) {
                        if (str_contains($attr->getName(), 'UploadableField')) {
                            $args = $attr->getArguments();
                            $fileNameProperty = $args['fileNameProperty'] ?? $args[0] ?? null;
                            if ($fileNameProperty) {
                                $mappings[$prop->getName()] = $fileNameProperty;
                                break;
                            }
                        }
                    }
                }
                $currentClass = $currentClass->getParentClass();
            }
        } catch (\Exception $e) {}
        return $mappings;
    }

    protected function getCamposExcluidosDetalle(): array
    {
        $excludes = [];
        $map = [
            'creado'      => ['creadoEl', 'creEl'],
            'creadoPor'   => ['creadoPor', 'crePor'],
            'modificado'  => ['modificadoEl', 'modEl', 'actualizadoEl', 'mdfEl'],
            'estado'      => ['estado'],
            'activo'      => ['activo', 'esActivo'],
            'evaluacionIA'=> ['resultadoEvaluacionIa'],
        ];

        foreach ($map as $templateKey => $properties) {
            $allDeprecated = true;
            $hasProperty   = false;
            foreach ($properties as $prop) {
                if ($this->hasField($prop)) {
                    $hasProperty = true;
                    if (!$this->isDeprecated($prop)) { $allDeprecated = false; break; }
                }
            }
            if ($hasProperty && $allDeprecated) $excludes[] = $templateKey;
        }

        return $excludes;
    }

    public function createEntity(string $entityFqcn): object
    {
        $entity = parent::createEntity($entityFqcn);
        if ($this->hasField('activo') && method_exists($entity, 'setActivo')) $entity->setActivo(true);
        return $entity;
    }

    public function persistEntity(EntityManagerInterface $entityManager, $entityInstance): void
    {
        try {
            parent::persistEntity($entityManager, $entityInstance);
        } catch (\Exception $e) {
            if (str_contains($e->getMessage(), 'PutObject') || str_contains($e->getMessage(), 'minio') || str_contains($e->getMessage(), 'cURL error 7')) {
                $this->addFlash('danger', '❌ Error de Almacenamiento: El servidor de archivos no está accesible. El registro se creó pero el archivo NO se pudo subir.');
                return;
            }
            throw $e;
        }
    }

    public function updateEntity(EntityManagerInterface $entityManager, $entityInstance): void
    {
        try {
            parent::updateEntity($entityManager, $entityInstance);
        } catch (\Exception $e) {
            if (str_contains($e->getMessage(), 'PutObject') || str_contains($e->getMessage(), 'minio') || str_contains($e->getMessage(), 'cURL error 7')) {
                $this->addFlash('danger', '❌ Error de Almacenamiento: No se pudo subir el archivo porque el servidor de archivos está fuera de línea.');
                return;
            }
            throw $e;
        }
    }

    protected function hasField(string $fieldName): bool
    {
        $entityFqcn = $this->getEntityFqcn();
        $reflection  = new \ReflectionClass($entityFqcn);
        return $reflection->hasProperty($fieldName) || $reflection->hasMethod('get' . ucfirst($fieldName));
    }

    protected function createTextField(string $property, string $label, bool $required = false, int $columns = 6): TextField
    {
        return TextField::new($property, $label)->setColumns($columns)->setRequired($required);
    }

    protected function createAssociationField(string $property, string $label, bool $required = false, int $columns = 6, ?string $pageName = null): AssociationField
    {
        $field = AssociationField::new($property, $label)->setColumns($columns)->setRequired($required);

        if ($pageName === Crud::PAGE_DETAIL) {
            $field->setTemplatePath('Admin/field/text_plain.html.twig');
        }

        $isAutocomplete = false;

        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if ($entityManager) {
                $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());
                if ($metadata->hasAssociation($property)) {
                    $mapping          = $metadata->getAssociationMapping($property);
                    $targetEntityName = $mapping['targetEntity'];
                    $count            = $entityManager->getRepository($targetEntityName)->count([]);

                    if ($count > 10 && !$this->isAuditField($property) && in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT])) {
                        $controllerFqcn = $this->guessCrudController($targetEntityName);
                        if ($controllerFqcn) {
                            $field->setCrudController($controllerFqcn);
                            $field->autocomplete();
                            $isAutocomplete = true;
                        }
                    }

                    if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT])) {
                        $filterType = static::RELATION_CONFIG[$property]['filter'] ?? null;
                        $sortFields = [];

                        if (property_exists($targetEntityName, 'nombre')) $sortFields = ['nombre'];
                        elseif (property_exists($targetEntityName, 'descripcion')) $sortFields = ['descripcion'];

                        if ($filterType || !empty($sortFields)) {
                            $field->setQueryBuilder(function ($qb) use ($filterType, $sortFields) {
                                if ($filterType) {
                                    match ($filterType) {
                                        'activos'           => $qb->andWhere('entity.estado = :estado')->setParameter('estado', 2),
                                        'retirados'         => $qb->andWhere('entity.estado = :estado')->setParameter('estado', 3),
                                        'preingreso'        => $qb->andWhere('entity.estado = :estado')->setParameter('estado', 1),
                                        'preingreso_activos'=> $qb->andWhere('entity.estado IN (:estados)')->setParameter('estados', [1, 2]),
                                        default             => null,
                                    };
                                }
                                $first = true;
                                foreach ($sortFields as $sField) {
                                    if ($first) { $qb->orderBy('entity.' . $sField, 'ASC'); $first = false; }
                                    else          $qb->addOrderBy('entity.' . $sField, 'ASC');
                                }
                                return $qb;
                            });
                        }
                    }

                    if ($pageName === Crud::PAGE_INDEX) {
                        $isToMany = $mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY;
                        if (!$isToMany) {
                            $field->setTemplatePath('@EasyAdmin/crud/field/text.html.twig');
                            $field->formatValue(function ($value) use ($property) {
                                if (null === $value) return '';
                                if (!is_object($value)) return (string) $value;
                                if (preg_match('/(creadoPor|crePor|modificadoPor|modPor)$/i', $property)) {
                                    if (method_exists($value, 'getIniciales')) return $value->getIniciales();
                                }
                                if (method_exists($value, 'getSigla')) return $value->getSigla();
                                if (method_exists($value, '__toString')) return (string) $value;
                                if (method_exists($value, 'getNombre')) return $value->getNombre();
                                if (method_exists($value, 'getId')) return '#' . $value->getId();
                                return (new \ReflectionClass($value))->getShortName();
                            });
                        }
                    }
                }
            }
        } catch (\Exception $e) {}

        if ($labelFromAttr = $this->getLabel($property, $pageName)) $field->setLabel($labelFromAttr);
        if ($pageName !== Crud::PAGE_INDEX) {
            if ($help = $this->getHelpText($property)) $field->setHelp($help);
        }

        $config = static::RELATION_CONFIG[$property] ?? [];
        if ($pageName !== Crud::PAGE_INDEX && $pageName !== Crud::PAGE_DETAIL) {
            $placeholder = $config['placeholder'] ?? true;
            if ($placeholder !== false) {
                if ($isAutocomplete) {
                    $text = is_string($placeholder) ? $placeholder : 'Filtrar...';
                    $field->setHtmlAttribute('data-placeholder', $text);
                    $field->setHtmlAttribute('placeholder', $text);
                } else {
                    $field->setFormTypeOption('placeholder', is_string($placeholder) ? $placeholder : 'Seleccionar...');
                }
            }
        }

        return $field;
    }

    protected function guessCrudController(string $entityFqcn): ?string
    {
        try {
            $entityName = (new \ReflectionClass($entityFqcn))->getShortName();
            $candidates = [
                'App\\Controller\\Admin\\' . $entityName . 'CrudController',
                'App\\Controller\\Admin\\Parametricas\\' . $entityName . 'CrudController',
            ];
            foreach ($candidates as $controller) {
                if (class_exists($controller) && method_exists($controller, 'getEntityFqcn') && $controller::getEntityFqcn() === $entityFqcn) {
                    return $controller;
                }
            }
        } catch (\Exception $e) {}
        return null;
    }

    protected function createTextareaField(string $property, string $label, bool $hideOnIndex = true, int $columns = 12): TextareaField
    {
        $field = TextareaField::new($property, $label)->setColumns($columns);
        if ($hideOnIndex) $field->hideOnIndex();
        return $field;
    }

    protected function createBooleanField(string $property, string $label, bool $renderAsSwitch = true): BooleanField
    {
        return BooleanField::new($property, $label)->renderAsSwitch($renderAsSwitch);
    }

    protected function hasField2(string $fieldName): bool
    {
        return $this->hasField($fieldName);
    }

    protected function getUploadUrl(): string
    {
        return '/uploads/';
    }

    protected function createImageField(string $property, string $label, string $uploadPath, ?string $pageName = null): TextField
    {
        return TextField::new($property, $label)
            ->formatValue(function ($value) { return $value ?? ''; });
    }

    public static function getSubscribedServices(): array
    {
        return array_merge(parent::getSubscribedServices(), [
            'local.storage'   => '?' . \League\Flysystem\FilesystemOperator::class,
            'docfile.storage' => '?' . \League\Flysystem\FilesystemOperator::class,
        ]);
    }
}
