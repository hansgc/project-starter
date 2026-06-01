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

    /**
     * Campos que NO deben aparecer en el listado (INDEX), pero sí en Detalle/Formularios.
     * Sobreescribir en controladores hijos.
     */
    public const INDEX_EXCLUDES = [];

    /**
     * Campos que deben aparecer en el listado (INDEX). Si se define,
     * se ignorarán INDEX_EXCLUDES y las reglas automáticas de exclusión.
     */
    public const INDEX_INCLUDES = [];

    /**
     * Campos que NO deben aparecer en la vista de detalle (DETAIL).
     * Sobreescribir en controladores hijos.
     */
    public const DETAIL_EXCLUDES = [];

    /**
     * Campos que NO deben aparecer en los formularios (NEW/EDIT).
     * Sobreescribir en controladores hijos.
     */
    public const FORM_EXCLUDES = [];

    /**
     * Campos que deben aparecer en los formularios (NEW/EDIT). Si se define,
     * se ignorarán FORM_EXCLUDES y las reglas automáticas de exclusión.
     */
    public const FORM_INCLUDES = [];

    /**
     * Orden personalizado de los campos. Si se define, se usará este orden
     * en lugar del orden automático o de INDEX_INCLUDES.
     */
    public const FIELDS_ORDER = [];
    
    /**
     * Etiquetas para la entidad. Si se definen como array ['Singular', 'Plural'], se usarán automáticamente.
     */
    public const ENTITY = null;

    /**
     * Nombre completo de la entidad. Los controladores hijos pueden definirlo si no usan App\Entity\\{NombreEntidad}.
     */
    public const ENTITY_FQCN = null;

    /**
     * Configuración especial para relaciones.
     * Permite aplicar filtros al autocompletado de campos específicos.
     * Ej: ['solicitadoPor' => ['filter' => 'activos']]
     * Opciones soportadas para Empleado: 'activos', 'retirados', 'todos'
     */
    public const RELATION_CONFIG = [];

    public function configureCrud(Crud $crud): Crud
    {
        // 1. Prioridad: Nueva constante ENTITY como array ['Singular', 'Plural']
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

    /**
     * Intenta determinar automáticamente qué campos deberían ser buscables.
     * Incluye campos de texto de la entidad y campos comunes en asociaciones.
     */
    protected function getAutoSearchFields(): array
    {
        $searchFields = ['id'];

        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return $searchFields;

            $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());

            // 1. Campos propios
            foreach ($metadata->fieldMappings as $fieldName => $mapping) {
                if ($this->isAuditField($fieldName) || $this->isExcludedFromIndex($fieldName)) continue;

                // Permitir búsqueda en strings, texto y números
                if (in_array($mapping['type'], ['string', 'text', 'integer', 'decimal'])) {
                    $searchFields[] = $fieldName;
                }
            }

            // 2. Asociaciones (Solo las que no son colecciones)
            foreach ($metadata->associationMappings as $assocName => $mapping) {
                if ($mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY) continue;
                if ($this->isAuditField($assocName) || $this->isExcludedFromIndex($assocName)) continue;

                // Agregar campos comunes de búsqueda en la entidad relacionada
                $searchFields[] = $assocName . '.id';
                
                // Si la entidad relacionada tiene 'nombre', 'sigla' o 'paterno', buscamos por ahí también
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
        // Intentar resolver la entidad a partir del nombre del controlador.
        // Ej: EmpleadoCrudController -> App\Entity\Empleado
        $controllerClass = get_called_class();
        $entityName = str_replace('CrudController', '', (new \ReflectionClass($controllerClass))->getShortName());

        if (empty($entityName)) {
            throw new \LogicException(sprintf(
                'No se pudo determinar la entidad desde %s. Defina getEntityFqcn() en el controlador hijo.',
                $controllerClass
            ));
        }

        try {
            $reflection = new \ReflectionClass(static::class);
            if ($reflection->hasConstant('ENTITY_FQCN')) {
                $entityFqcn = $reflection->getConstant('ENTITY_FQCN');
                if (is_string($entityFqcn) && $entityFqcn !== '') {
                    return $entityFqcn;
                }
            }
        } catch (\ReflectionException $e) {}

        $candidates = [
            'App\\Entity\\' . $entityName,
        ];

        foreach ($candidates as $candidate) {
            if (class_exists($candidate)) {
                return $candidate;
            }
        }

        throw new \RuntimeException(sprintf(
            'No se pudo autodetectar la entidad para %s. Defina getEntityFqcn() manualmente o establezca la constante ENTITY_FQCN en el controlador hijo.',
            $controllerClass
        ));
    }

    /**
     * Permite definir el orden de los campos de forma sencilla en los hijos.
     * Retorna un array con los nombres de los campos en el orden deseado.
     */
    protected function getFieldsOrder(): array
    {
        if (!empty(static::FIELDS_ORDER)) {
            return static::FIELDS_ORDER;
        }

        return static::INDEX_INCLUDES;
    }

    /**
     * Configura las opciones generales del CRUD.
     * Agrega la acción DETAIL a la página INDEX por defecto.
     */
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

    /**
     * Configura filtros básicos comunes.
     * Los controladores hijos deben usar $this->applyFilters($filters, ['filtro1', 'filtro2'])
     */
    public function configureFilters(Filters $filters): Filters
    {
        return $this->applyFilters($filters);
    }

    /**
     * Aplica filtros estándar y adicionales solo si hay suficientes registros.
     * Este es el método que deben usar los controladores hijos.
     */
    protected function applyFilters(Filters $filters, array $additionalFilters = []): Filters
    {
        // Si no hay suficientes registros, no mostrar filtros
        if (!$this->shouldShowFilters()) return $filters;

        // Agregar filtros estándar si existen los campos
        $filters->add('id');

        if ($this->hasField('nombre')) $filters->add(CaseInsensitiveTextFilter::new('nombre'));
        if ($this->hasField('activo')) $filters->add('activo');
        if ($this->hasField('creadoEl')) $filters->add('creadoEl');

        // Agregar filtros adicionales
        foreach ($additionalFilters as $filter) {
            if (is_string($filter)) {
                // Si es un campo de texto, usar el filtro case-insensitive
                if ($this->isTextField($filter)) $filters->add(CaseInsensitiveTextFilter::new($filter));
                else $filters->add($filter);
            } else $filters->add($filter);
        }
        
        return $filters;
    }

    /**
     * Verifica si una propiedad es de tipo texto/string.
     */
    protected function isTextField(string $propertyName): bool
    {
        try {
            $reflection = new \ReflectionClass($this->getEntityFqcn());
            if (!$reflection->hasProperty($propertyName)) return false;
            
            $property = $reflection->getProperty($propertyName);
            $type = $property->getType();
            
            if (!$type) return false;
            
            // Verificar si es string y no es una relación (aunque las relaciones suelen ser objetos)
            return $type->getName() === 'string';
        } catch (\Exception $e) {return false;}
    }

    /**
     * Determina si se deben mostrar los filtros basado en la cantidad de registros.
     * Retorna false si la cantidad de registros es menor o igual al tamaño de página (20).
     */
    protected function shouldShowFilters(): bool
    {
        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return true;
            
            $count = $entityManager->getRepository($this->getEntityFqcn())->count([]);
            
            // Si hay 20 o menos registros (una sola página), no necesitamos filtros
            return $count > 20;
        } catch (\Exception $e) {return true;}
    }

    /**
     * Verifica si una propiedad tiene la anotación @deprecated.
     */
    protected function isDeprecated(string $fieldName): bool
    {
        try {
            $reflection = new \ReflectionProperty($this->getEntityFqcn(), $fieldName);
            $docComment = $reflection->getDocComment();
            return $docComment && str_contains($docComment, '@deprecated');
        } catch (\Exception $e) {return false;}
    }

    public function configureFields(string $pageName): iterable
    {
        $fields = iterator_to_array($this->getAutoFields($pageName));
        $order = $this->getFieldsOrder();

        // 1. Definir campos con prioridad absoluta al inicio (Auditoría Técnica)
        $priorityHead = ['id', 'creadoEl', 'creEl', 'creadoPor', 'crePor', 'empleado'];
        
        $orderedFields = [];
        $addedProperties = [];

        // 2. Primero: Añadir los campos de prioridad que NO están en el orden personalizado
        // (Si están en el orden personalizado, se respetará el lugar que el usuario les dé)
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

        // 3. Segundo: Añadir los campos definidos en getFieldsOrder()
        foreach ($order as $fieldName) {
            foreach ($fields as $field) {
                if ($field->getAsDto()->getProperty() === $fieldName) {
                    $orderedFields[] = $field;
                    $addedProperties[] = $fieldName;
                    break;
                }
            }
        }

        // 4. Tercero: Añadir el resto de campos que falten
        foreach ($fields as $field) {
            $property = $field->getAsDto()->getProperty();
            if (!in_array($property, $addedProperties)) {
                $orderedFields[] = $field;
            }
        }

        // --- NUEVA LÓGICA PARA CAMPOS DESHABILITADOS ---
        if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT])) {
            foreach ($orderedFields as $field) {
                $propertyName = $field->getAsDto()->getProperty();
                if ($propertyName && $this->isFieldDisabledInAttr($propertyName)) {
                    // Esto deshabilita el input HTML y evita que Symfony procese cambios en el submit
                    $field->setFormTypeOption('disabled', true);
                }
            }
        }
        // -----------------------------------------------

        return $orderedFields;
    }

    /**
     * Determina si un campo es de auditoría o técnico.
     */
    protected function isAuditField(string $fieldName): bool
    {
        if (in_array($fieldName, self::AUDIT_FIELDS)) return true;
        
        // Campos que finalizan en "Anular", "Cambios", "Pin" o "Revision" (insensible a mayúsculas)
        return (bool) preg_match('/(Anular|Cambios|Pin|Revision)$/i', $fieldName);
    }

    /**
     * Determina si un campo debe ser excluido de la vista INDEX.
     */
    protected function isExcludedFromIndex(string $fieldName): bool
    {
        // Campos "Protegidos" que siempre queremos ver por defecto
        $essentialFields = ['id', 'empleado', 'creadoEl', 'creEl', 'creadoPor', 'crePor'];
        if (in_array($fieldName, $essentialFields)) return false;

        // 1. Si hay una lista blanca (INCLUDES), solo permitimos lo que esté allí
        if (!empty(static::INDEX_INCLUDES)) {
            return !in_array($fieldName, $this->getFieldsOrder());
        }

        // 2. Si no hay lista blanca, aplicamos lista negra (EXCLUDES) y reglas automáticas
        if (in_array($fieldName, static::INDEX_EXCLUDES)) return true;
        
        // Regla: No mostrar campos con sufijos técnicos o sensibles en el listado
        return (bool) preg_match('/(Cambios|Anular|Pin|Revision|Observacion|password)$/i', $fieldName);
    }

    /**
     * Determina si un campo debe ser excluido de los formularios (NEW/EDIT).
     */
    protected function isExcludedFromForm(string $fieldName, string $pageName): bool
    {
        if ($pageName !== Crud::PAGE_NEW && $pageName !== Crud::PAGE_EDIT) return false;

        // 1. Si hay una lista blanca (INCLUDES), solo permitimos lo que esté allí
        if (!empty(static::FORM_INCLUDES)) {
            return !in_array($fieldName, static::FORM_INCLUDES);
        }

        // 2. Si no hay lista blanca, aplicamos lista negra (EXCLUDES)
        return in_array($fieldName, static::FORM_EXCLUDES);
    }

    /**
     * Obtiene la etiqueta para un campo.
     * Prioriza atajos estáticos, luego AdminLabel y retorna null si no encuentra nada.
     */
    protected function getLabel(string $fieldName, string $pageName): ?string
    {
        $preferShort = ($pageName === Crud::PAGE_INDEX);

        // 1. Atajos estáticos globales
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

        // 2. Buscar en el atributo AdminLabel
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
                        if ($preferShort && $adminLabel->short) {
                            return $adminLabel->short;
                        }
                        return $adminLabel->full;
                    }
                }
            }
        } catch (\Exception $e) {}

        return null;
    }

    /**
     * Obtiene el texto de ayuda para un campo, priorizando AdminLabel(memo)
     * y cayendo en deducción automática desde validaciones (Assert\File).
     */
    protected function getHelpText(string $fieldName): ?string
    {
        try {
            $entityFqcn = static::getEntityFqcn();
            $reflection = new \ReflectionClass($entityFqcn);
            
            // Buscar la propiedad en toda la jerarquía de clases
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
            
            // 1. Prioridad: AdminLabel(memo) de forma robusta
            foreach ($prop->getAttributes() as $attr) {
                if (str_contains($attr->getName(), 'AdminLabel')) {
                    $memo = $attr->newInstance()->memo;
                    if ($memo) return $memo;
                    break;
                }
            }
            
            // 2. Deducción por validaciones (VichUploader / Files)
            foreach ($prop->getAttributes() as $attr) {
                $name = $attr->getName();
                // Verificamos si es una restricción de File o Image
                if (str_contains($name, 'Constraints\\File') || str_contains($name, 'Constraints\\Image')) {
                    $args = $attr->getArguments();
                    
                    // 2.1. Intentar usar el mensaje personalizado de la validación si existe
                    if (isset($args['mimeTypesMessage'])) {
                        return $args['mimeTypesMessage'];
                    }

                    // 2.2. Si no hay mensaje, intentar deducirlo de los mimeTypes
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
                        if (!empty($extensions)) {
                            return 'Solo archivos: ' . implode(', ', array_unique($extensions));
                        }
                    }
                }
            }
        } catch (\Exception $e) {}
        
        return null;
    }

    /**
     * Verifica si un campo está marcado como deshabilitado en el atributo AdminLabel.
     */
    protected function isFieldDisabledInAttr(string $fieldName): bool
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

            if ($prop) {
                foreach ($prop->getAttributes() as $attr) {
                    if (str_contains($attr->getName(), 'AdminLabel')) {
                        $adminLabel = $attr->newInstance();
                        return (bool) $adminLabel->disabled;
                    }
                }
            }
        } catch (\Exception $e) {}

        return false;
    }

    protected function getAutoFields(string $pageName, array $excluded = []): iterable
    {
        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if (!$entityManager) return;

            $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());
            
            // 1. Detección automática de campos VichUploader
            $vichMappings = $this->getVichMappings();
            $vichFileProperties = array_keys($vichMappings);
            $vichNameProperties = array_values($vichMappings);
            
            // 2. Definir exclusiones base (ID y Password se manejan aparte)
            // Agregamos 'observacion' y 'observaciones' para manejarlos al final del formulario
            $allExcludes = array_merge($excluded, ['id', 'password', 'observacion', 'observaciones']);

            // 2.1. Agregar exclusiones específicas para Detalle
            if ($pageName === Crud::PAGE_DETAIL) {
                // Excluir campos que ya se muestran en la cabecera (AUDIT_FIELDS) del layout custom_detail
                $allExcludes = array_merge($allExcludes, static::AUDIT_FIELDS, static::DETAIL_EXCLUDES, $this->getCamposExcluidosDetalle());
            }

            // 3. Agregar ID primero (solo en índice)
            if (!in_array('id', $excluded)) {
                yield IdField::new('id', 'ID')->onlyOnIndex();
            }

            // 3.1. TRUCO DE PRIORIDAD: Campos esenciales al principio
            $priorityFields = ['empleado', 'creadoEl', 'creEl', 'creadoPor', 'crePor'];
            foreach ($priorityFields as $pField) {
                if (!in_array($pField, $excluded) && !$this->isExcludedFromIndex($pField) && $this->hasField($pField)) {
                    $assocMetadata = $metadata->associationMappings[$pField] ?? null;
                    
                    // Determinar etiqueta (personalizada via getLabel o automática)
                    $label = $this->getLabel($pField, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $pField));

                    if ($assocMetadata) {
                        $required = false;
                        if (isset($assocMetadata['joinColumns'][0]['nullable'])) {
                            $required = !$assocMetadata['joinColumns'][0]['nullable'];
                        }
                        $field = $this->createAssociationField($pField, $label, $required, 6, $pageName);
                    } else {
                        $mapping = $metadata->fieldMappings[$pField];
                        $field = $this->createFieldByType($pField, $mapping['type'], $pageName)
                            ->setLabel($label)
                            ->setRequired(!($mapping['nullable'] ?? true));
                    }

                    if ($field) {
                        // 1. Ocultar en formularios si es un campo de auditoría
                        if ($this->isAuditField($pField)) {
                            $field->hideOnForm();
                        }
                        
                        // 2. Ocultar si está explícitamente excluido del formulario en el controlador hijo
                        if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($pField, $pageName)) {
                            $field->hideOnForm();
                        }

                        $allExcludes[] = $pField;
                        yield $field;
                    }
                }
            }

            // 4. Mapear campos de la base de datos (Doctrine)
            foreach ($metadata->fieldMappings as $fieldName => $mapping) {
                if (in_array($fieldName, $allExcludes) || in_array($fieldName, $vichFileProperties) || in_array($fieldName, $vichNameProperties) || $this->isDeprecated($fieldName)) continue;
                
                // Ocultar si está definido en INDEX_EXCLUDES o cumple patrones de exclusión para la página INDEX
                if ($pageName === Crud::PAGE_INDEX && $this->isExcludedFromIndex($fieldName)) continue;

                // Ocultar si está definido en FORM_EXCLUDES o no está en FORM_INCLUDES
                if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($fieldName, $pageName)) continue;

                $required = !($mapping['nullable'] ?? true);
                $field = $this->createFieldByType($fieldName, $mapping['type'], $pageName)
                    ->setRequired($required);
                

                
                // Ocultar campos de auditoría si cumplen las reglas
                if ($this->isAuditField($fieldName)) {
                    $field->hideOnForm();
                }
                
                yield $field;
            }

            // 5. Mapear asociaciones
            foreach ($metadata->associationMappings as $assocName => $mapping) {
                if (in_array($assocName, $allExcludes) || $this->isDeprecated($assocName)) continue;
                
                // Ocultar si está definido en FORM_EXCLUDES o no está en FORM_INCLUDES
                if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT]) && $this->isExcludedFromForm($assocName, $pageName)) continue;

                $isToMany = $mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY;
                
                // Ocultar colecciones inversas de auditoría (quién creó/modificó qué) en todas las vistas
                // Esto evita errores de esquema en tablas técnicas y carga excesiva de datos
                if ($isToMany && isset($mapping['mappedBy']) && $this->isAuditField($mapping['mappedBy'])) {
                    continue;
                }
                
                if ($pageName === Crud::PAGE_INDEX) {
                    if ($isToMany) continue; // Ocultar colecciones en Index
                    
                    // Ocultar si no cumple reglas de inclusión/exclusión para la página INDEX
                    if ($this->isExcludedFromIndex($assocName)) continue;

                    // Determinar etiqueta (personalizada via getLabel o automática)
                    $label = $this->getLabel($assocName, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $assocName));
                    
                    // Usar AssociationField con plantilla personalizada para evitar links pero conservar acceso nativo
                    yield AssociationField::new($assocName, $label)
                        ->setTemplatePath('Admin/field/text_plain.html.twig')
                        ->formatValue(function ($value) use ($assocName) {
                            if (null === $value) return '';
                            // Lógica de formateo inteligente para extraer el texto legible
                            if (is_object($value)) {
                                // 1. Prioridad: Sigla para ahorrar espacio en tablas del Index (todas las entidades)
                                if (method_exists($value, 'getSigla')) return $value->getSigla();

                                // 2. Especial: Iniciales SOLO para campos de auditoría de personal (creadoPor, modificadoPor, etc.)
                                if (preg_match('/(creadoPor|crePor|modificadoPor|modPor)$/i', $assocName)) {
                                    if (method_exists($value, 'getIniciales')) return $value->getIniciales();
                                }

                                // 3. Fallbacks si no hay sigla (o iniciales en caso de auditoría)
                                if (method_exists($value, '__toString')) return (string) $value;
                                if (method_exists($value, 'getNombre')) return $value->getNombre();
                                if (method_exists($value, 'getId')) return '#' . $value->getId();
                                return (new \ReflectionClass($value))->getShortName();
                            }
                            return (string) $value;
                        });
                } else {
                    $required = false;
                    if (isset($mapping['joinColumns'][0]['nullable'])) {
                        $required = !$mapping['joinColumns'][0]['nullable'];
                    }
                    $field = $this->createAssociationField($assocName, ucfirst($assocName), $required, 6, $pageName);
                    
                    if ($this->isAuditField($assocName)) {
                        $field->hideOnForm();
                    }

                    // Ocultar asociaciones complejas por defecto en Detalle y Formularios.
                    $isInverse = isset($mapping['mappedBy']);
                    
                    if ($isToMany || $isInverse) {
                        $field->hideOnDetail();
                        $field->hideOnForm();
                    }

                    yield $field;
                }
            }

            // 6. Agregar campos VichUploader (Formulario y Visualización)
            foreach ($vichMappings as $fileField => $nameField) {
                if (in_array($fileField, $allExcludes) || in_array($nameField, $allExcludes)) continue;
                
                // Prioridad de etiqueta: Atributo en el campo de base de datos (nameField), luego en el de archivo (fileField), luego default
                $label = $this->getLabel($nameField, $pageName) 
                    ?? $this->getLabel($fileField, $pageName) 
                    ?? ucfirst(preg_replace('/File$/', '', $fileField));
                
                if ($pageName !== Crud::PAGE_INDEX && $pageName !== Crud::PAGE_DETAIL) {
                    // Ocultar si está definido en FORM_EXCLUDES o no está en FORM_INCLUDES
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

            // 7. Mapeo de campos de observaciones (siempre al final y de ancho completo)
            foreach (['observacion', 'observaciones'] as $obsField) {
                if (!$this->hasField($obsField)) continue;
                if ($this->isExcludedFromForm($obsField, $pageName)) continue;
                
                yield $this->createTextareaField($obsField, ucfirst($obsField), true, 12);
            }

        } catch (\Exception $e) {}
    }

    /**
     * Crea un campo de EasyAdmin basado en el tipo de Doctrine.
     */
    protected function createFieldByType(string $propertyName, string $doctrineType, string $pageName): FieldInterface
    {
        $label = $this->getLabel($propertyName, $pageName) ?? ucfirst(preg_replace('/(?<!^)[A-Z]/', ' $0', $propertyName));
        
        $field = match ($doctrineType) {
            'integer', 'smallint', 'bigint' => IntegerField::new($propertyName, $label),
            'decimal', 'float' => NumberField::new($propertyName, $label),
            'boolean' => BooleanField::new($propertyName, $label)->renderAsSwitch($pageName !== Crud::PAGE_INDEX),
            'datetime', 'datetimetz' => DateTimeField::new($propertyName, $label)->setFormat('dd/MM/yyyy HH:mm'),
            'date' => DateField::new($propertyName, $label)->setFormat('dd/MM/yyyy'),
            'time' => TimeField::new($propertyName, $label),
            'text' => TextareaField::new($propertyName, $label)->hideOnIndex(),
            'array', 'json' => ArrayField::new($propertyName, $label),
            'string' => $this->guessStringField($propertyName, $label),
            default => TextField::new($propertyName, $label),
        };

        // Aplicar texto de ayuda (memo) si existe y estamos fuera del Index
        if ($pageName !== Crud::PAGE_INDEX) {
            if ($help = $this->getHelpText($propertyName)) {
                $field->setHelp($help);
            }
        }

        return $field->setColumns(6);
    }

    /**
     * Intenta adivinar el mejor campo para un string (Email, URL, etc).
     */
    protected function guessStringField(string $propertyName, string $label): FieldInterface
    {
        if (str_contains(strtolower($propertyName), 'email')) return EmailField::new($propertyName, $label);
        if (str_contains(strtolower($propertyName), 'url') || str_contains(strtolower($propertyName), 'web')) return UrlField::new($propertyName, $label);
        
        // Si el nombre sugiere que es largo, usar textarea
        if (preg_match('/(descripcion|comentario|nota|detalle)/i', $propertyName)) {
            return TextareaField::new($propertyName, $label)->hideOnIndex();
        }

        return TextField::new($propertyName, $label);
    }

    /**
     * Escanea la entidad en busca de atributos Vich\UploadableField.
     * Retorna array [propiedadArchivo => propiedadNombreBD]
     */
    protected function getVichMappings(): array
    {
        $mappings = [];
        try {
            $reflection = new \ReflectionClass(static::getEntityFqcn());
            $currentClass = $reflection;
            
            while ($currentClass) {
                foreach ($currentClass->getProperties() as $prop) {
                    // Evitar duplicados si la propiedad está sobreescrita
                    if (isset($mappings[$prop->getName()])) continue;
 
                    foreach ($prop->getAttributes() as $attr) {
                        if (str_contains($attr->getName(), 'UploadableField')) {
                            $args = $attr->getArguments();
                            // Soporte para argumentos nombrados o posicionales
                            $fileNameProperty = $args['fileNameProperty'] ?? $args[1] ?? $args[0] ?? null;
                            
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

    /**
     * Define los campos a excluir en la vista de detalle para este controller
     * Los controllers hijos pueden sobreescribir este método para personalizar exclusiones
     */
    protected function getCamposExcluidosDetalle(): array
    {
        $excludes = [];
        
        // Mapeo de llaves del template (layout_detail) a propiedades de la entidad
        $map = [
            'creado' => ['creadoEl', 'creEl'],
            'creadoPor' => ['creadoPor', 'crePor'],
            'modificado' => ['modificadoEl', 'modEl', 'actualizadoEl', 'mdfEl'],
            'estado' => ['estado'],
            'activo' => ['activo', 'esActivo'],
            'evaluacionIA' => ['resultadoEvaluacionIa']
        ];

        foreach ($map as $templateKey => $properties) {
            $allDeprecated = true;
            $hasProperty = false;
            foreach ($properties as $prop) {
                if ($this->hasField($prop)) {
                    $hasProperty = true;
                    if (!$this->isDeprecated($prop)) {
                        $allDeprecated = false;
                        break;
                    }
                }
            }
            // Si el campo existe pero está marcado como @deprecated, lo excluimos de la cabecera
            if ($hasProperty && $allDeprecated) {
                $excludes[] = $templateKey;
            }
        }

        return $excludes;
    }

    /**
     * Crea una nueva instancia de la entidad con valores por defecto.
     * Establece 'activo' = true si la entidad tiene ese campo.
     */
    public function createEntity(string $entityFqcn): object
    {
        $entity = parent::createEntity($entityFqcn);
        
        // Establecer activo = true por defecto si la entidad tiene ese campo
        if ($this->hasField('activo') && method_exists($entity, 'setActivo')) $entity->setActivo(true);
        
        // Establecer crePor / creadoPor con el empleado del usuario actual
        $user = $this->getUser();
        if ($user instanceof \App\Entity\Usuario && $user->getEmpleado()) {
            if ($this->hasField('crePor') && method_exists($entity, 'setCrePor')) $entity->setCrePor($user->getEmpleado());
            elseif ($this->hasField('creadoPor') && method_exists($entity, 'setCreadoPor')) $entity->setCreadoPor($user->getEmpleado());
        }
        
        return $entity;
    }

    public function persistEntity(EntityManagerInterface $entityManager, $entityInstance): void
    {
        try {
            parent::persistEntity($entityManager, $entityInstance);
        } catch (\Exception $e) {
            if (str_contains($e->getMessage(), 'PutObject') || str_contains($e->getMessage(), 'minio') || str_contains($e->getMessage(), 'cURL error 7')) {
                $this->addFlash('danger', '❌ Error de Almacenamiento: El servidor de archivos (MinIO) no está accesible. El registro se creó pero el archivo NO se pudo subir.');
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
                $this->addFlash('danger', '❌ Error de Almacenamiento: No se pudo subir el archivo porque el servidor MinIO está fuera de línea.');
                return;
            }
            throw $e;
        }
    }

    /**
     * Verifica si la entidad tiene un campo específico.
     * Útil para campos opcionales como 'activo', 'nombre', etc.
     */
    protected function hasField(string $fieldName): bool
    {
        $entityFqcn = $this->getEntityFqcn();
        $reflection = new \ReflectionClass($entityFqcn);

        return $reflection->hasProperty($fieldName) || $reflection->hasMethod('get' . ucfirst($fieldName));
    }

    /**
     * Configura etiquetas estándar para entidades.
     * Los controladores hijos pueden usar esto para mantener consistencia.
     */
    protected function setStandardEntityLabels(Crud $crud, string $singular, string $plural): Crud
    {
        return $crud
            ->setEntityLabelInSingular($singular)
            ->setEntityLabelInPlural($plural);
    }

    /**
     * Configura campos de búsqueda estándar.
     */
    protected function setStandardSearchFields(Crud $crud, array $fields): Crud
    {
        return $crud->setSearchFields($fields);
    }

    /**
     * Campo de texto estándar con configuración común.
     */
    protected function createTextField(string $property, string $label, bool $required = false, int $columns = 6): TextField
    {
        return TextField::new($property, $label)
            ->setColumns($columns)
            ->setRequired($required);
    }

    protected function createAssociationField(string $property, string $label, bool $required = false, int $columns = 6, ?string $pageName = null): AssociationField
    {
        $field = AssociationField::new($property, $label)
            ->setColumns($columns)
            ->setRequired($required);

        if ($pageName === Crud::PAGE_DETAIL) {
            $field->setTemplatePath('Admin/field/text_plain.html.twig');
        }

        $isAutocomplete = false;

        // Lógica dinámica: autocompletar solo si la tabla es grande (>10)
        try {
            $entityManager = $this->container->get('doctrine')->getManagerForClass($this->getEntityFqcn());
            if ($entityManager) {
                $metadata = $entityManager->getClassMetadata($this->getEntityFqcn());
                if ($metadata->hasAssociation($property)) {
                    $mapping = $metadata->getAssociationMapping($property);
                    $targetEntityName = $mapping['targetEntity'];
                    $count = $entityManager->getRepository($targetEntityName)->count([]);
                    
                    // Si es tabla grande, NO es de auditoría y ESTAMOS EN UN FORMULARIO, aplicar autocompletado
                    // CRÍTICO: Solo si existe un controlador CRUD para la entidad destino
                    if ($count > 10 && !$this->isAuditField($property) && in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT])) {
                        $controllerFqcn = $this->guessCrudController($targetEntityName);
                        if ($controllerFqcn) {
                            $field->setCrudController($controllerFqcn);
                            $field->autocomplete();
                            $isAutocomplete = true;
                        }
                    }

                    // Lógica general de QueryBuilder (filtrado y ordenación) para formularios
                    if (in_array($pageName, [Crud::PAGE_NEW, Crud::PAGE_EDIT])) {
                        $filterType = static::RELATION_CONFIG[$property]['filter'] ?? null;
                        
                        $sortFields = [];
                        if ($targetEntityName === \App\Entity\Externa\Personal\Archivo\Empleado::class) {
                            $sortFields = ['paterno', 'materno', 'nombre'];
                        } elseif (property_exists($targetEntityName, 'nombre')) {
                            $sortFields = ['nombre'];
                        } elseif (property_exists($targetEntityName, 'descripcion')) {
                            $sortFields = ['descripcion'];
                        }

                        if ($filterType || !empty($sortFields)) {
                            $field->setQueryBuilder(function ($queryBuilder) use ($filterType, $sortFields) {
                                if ($filterType) {
                                    switch ($filterType) {
                                        case 'activos':
                                            $queryBuilder->andWhere('entity.estado = :estado')->setParameter('estado', 2);
                                            break;
                                        case 'retirados':
                                            $queryBuilder->andWhere('entity.estado = :estado')->setParameter('estado', 3);
                                            break;
                                        case 'preingreso':
                                            $queryBuilder->andWhere('entity.estado = :estado')->setParameter('estado', 1);
                                            break;
                                        case 'preingreso_activos':
                                            $queryBuilder->andWhere('entity.estado IN (:estados)')->setParameter('estados', [1, 2]);
                                            break;
                                    }
                                }

                                if (!empty($sortFields)) {
                                    $first = true;
                                    foreach ($sortFields as $sField) {
                                        if ($first) {
                                            $queryBuilder->orderBy('entity.' . $sField, 'ASC');
                                            $first = false;
                                        } else {
                                            $queryBuilder->addOrderBy('entity.' . $sField, 'ASC');
                                        }
                                    }
                                }
                                return $queryBuilder;
                            });
                        }
                    }

                    // Formateo inteligente para asociaciones en INDEX (previene errores de __toString y quita enlaces)
                    if ($pageName === Crud::PAGE_INDEX) {
                        $isToMany = $mapping['type'] & \Doctrine\ORM\Mapping\ClassMetadata::TO_MANY;
                        if (!$isToMany) {
                            $field->setTemplatePath('@EasyAdmin/crud/field/text.html.twig');
                            $field->formatValue(function ($value) use ($property) {
                                if (null === $value) return '';
                                if (!is_object($value)) return (string) $value;

                                // 1. Especial: Iniciales para campos de auditoria (creadoPor, crePor, etc.)
                                if (preg_match('/(creadoPor|crePor|modificadoPor|modPor)$/i', $property)) {
                                    if (method_exists($value, 'getIniciales')) return $value->getIniciales();
                                }

                                // 2. General: Sigla si existe (para ahorrar espacio)
                                if (method_exists($value, 'getSigla')) return $value->getSigla();

                                // 3. Fallbacks de nombre legible
                                if (method_exists($value, '__toString')) return (string) $value;
                                if (method_exists($value, 'getNombre')) return $value->getNombre();
                                if (method_exists($value, 'getId')) return '#' . $value->getId();
                                
                                return (new \ReflectionClass($value))->getShortName();
                            });
                        }
                    }
                }
            }
        } catch (\Exception $e) {
            // En caso de error, EasyAdmin usará su configuración por defecto
        }

        // Aplicar etiqueta desde atributo AdminLabel si existe
        if ($labelFromAttr = $this->getLabel($property, $pageName)) {
            $field->setLabel($labelFromAttr);
        }

        // Aplicar texto de ayuda (memo) si existe y estamos fuera del Index
        if ($pageName !== Crud::PAGE_INDEX) {
            if ($help = $this->getHelpText($property)) {
                $field->setHelp($help);
            }
        }

        // Configuración adicional desde RELATION_CONFIG
        $config = static::RELATION_CONFIG[$property] ?? [];

        // Placeholder: Configurar texto diferente si es select normal o autocomplete
        // Se puede sobreescribir con RELATION_CONFIG['placeholder'] o deshabilitar con false
        if ($pageName !== Crud::PAGE_INDEX && $pageName !== Crud::PAGE_DETAIL) {
            $placeholder = $config['placeholder'] ?? true;
            if ($placeholder !== false) {
                if ($isAutocomplete) {
                    $text = is_string($placeholder) ? $placeholder : 'Filtrar...';
                    $field->setHtmlAttribute('data-placeholder', $text);
                    $field->setHtmlAttribute('placeholder', $text);
                } else {
                    $field->setFormTypeOption(
                        'placeholder',
                        is_string($placeholder) ? $placeholder : 'Seleccionar...'
                    );
                }
            }
        }


        return $field;
    }

    /**
     * Intenta encontrar el controlador CRUD para una entidad determinada basándose en convenciones de nombres.
     */
    protected function guessCrudController(string $entityFqcn): ?string
    {
        try {
            $entityName = (new \ReflectionClass($entityFqcn))->getShortName();
            $possibleControllers = [
                'App\\Controller\\Admin\\' . $entityName . 'CrudController',
                'App\\Controller\\Admin\\Parametricas\\' . $entityName . 'CrudController',
                'App\\Controller\\Admin\\Adm\\' . $entityName . 'CrudController',
            ];

            foreach ($possibleControllers as $controller) {
                if (class_exists($controller)) {
                    if (method_exists($controller, 'getEntityFqcn') && $controller::getEntityFqcn() === $entityFqcn) {
                        return $controller;
                    }
                }
            }
        } catch (\Exception $e) {}

        return null;
    }

    /**
     * Campo de texto grande estándar.
     */
    protected function createTextareaField(string $property, string $label, bool $hideOnIndex = true, int $columns = 12): TextareaField
    {
        $field = TextareaField::new($property, $label)->setColumns($columns);
        
        if ($hideOnIndex) $field->hideOnIndex();
        
        return $field;
    }

    /**
     * Campo booleano estándar.
     */
    protected function createBooleanField(string $property, string $label, bool $renderAsSwitch = true): BooleanField
    {
        return BooleanField::new($property, $label)->renderAsSwitch($renderAsSwitch);
    }

    /**
     * Crea un campo visual para mostrar el estado de evaluación IA con círculos de colores
     * Reutilizable en cualquier controller que tenga el campo resultadoEvaluacionIa
     */
    protected function createEvaluationStatusField(string $fieldName = 'estadoEvaluacionIa', string $label = 'IA'): \EasyCorp\Bundle\EasyAdminBundle\Field\TextField
    {
        return \EasyCorp\Bundle\EasyAdminBundle\Field\TextField::new($fieldName, $label)
            ->onlyOnIndex()
            ->setColumns(1)
            ->formatValue(function ($value, $entity) {
                if (!method_exists($entity, 'getResultadoEvaluacionIa')) {
                    return '−';
                }
                
                $resultado = $entity->getResultadoEvaluacionIa();
                
                if ($resultado === null || $resultado === '') {
                    return '−';
                }
                
                if (str_contains($resultado, 'ERROR') || str_contains($resultado, 'CUOTA EXCEDIDA')) {
                    return '🔴';
                }
                
                if (preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $resultado)) {
                    return '🔵';
                }
                
                return '⚫';
            });
    }

    /**
     * Agrega filtros estándar para una entidad.
     */
    protected function addStandardFilters(Filters $filters, array $additionalFields = []): Filters
    {
        if ($this->hasField('nombre')) $filters->add('nombre');
        
        foreach ($additionalFields as $field) {
            if ($this->hasField($field)) $filters->add($field);
        }
        
        return $filters;
    }

    /**
     * Agrega campos de búsqueda a los predeterminados (id, nombre).
     * Úsalo en los controladores hijos en lugar de setSearchFields para no perder los campos base.
     */
    protected function addSearchFields(Crud $crud, array $extraFields): Crud
    {
        $searchFields = ['id'];
        if ($this->hasField('nombre')) $searchFields[] = 'nombre';
        if ($this->hasField('empleado')) {
            $searchFields = array_merge($searchFields, [
                'empleado.id',
                'empleado.nombre',
                'empleado.paterno',
                'empleado.materno'
            ]);
        }

        return $crud->setSearchFields(array_unique(array_merge($searchFields, $extraFields)));
    }

    public function configureAssets(Assets $assets): Assets
    {
        return $assets->addJsFile('js/empleado-validator.js?v=7')
                      ->addCssFile('css/image-modal.css')
                      ->addJsFile('js/image-modal.js');
    }

    /**
     * Formatea el valor de un campo de imagen para mostrar un icono con modal o el PDF.
     */
    protected function formatImageValue(?string $value, string $pageName, string $suffix, string $uploadPath): string
    {
        if (!$value) {
            return '';
        }

        $url = $uploadPath . $value;
        $assets = ''; // Se podría usar para inyectar CSS/JS si fuera necesario

        if (str_ends_with(strtolower($value), '.pdf')) {
            $text = ($pageName === Crud::PAGE_INDEX) ? '' : 'Descargar PDF';
            return sprintf(
                '<a href="%s" target="_blank" style="display: inline-flex; align-items: center; text-decoration: none; color: #007bff;" title="Descargar PDF">
                    <svg width="20" height="20" fill="currentColor" style="margin-right: %s;" viewBox="0 0 16 16">
                        <path d="M14 14V4.5L9.5 0H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2zM9.5 3A1.5 1.5 0 0 0 11 4.5h2V14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1h5.5v2z"/>
                        <path d="M4.603 14.087a.81.81 0 0 1-.438-.42c-.195-.388-.13-.776.08-1.102.198-.307.526-.568.897-.787a7.68 7.68 0 0 1 1.482-.645 19.697 19.697 0 0 0 1.062-2.227 7.269 7.269 0 0 1-.43-1.295c-.086-.4-.119-.796-.046-1.136.075-.354.274-.672.65-.823.192-.077.4-.12.602-.077a.7.7 0 0 1 .477.365c.088.164.12.356.127.538.007.188-.012.396-.047.614-.084.51-.27 1.134-.52 1.794a10.954 10.954 0 0 0 .98 1.686 5.753 5.753 0 0 1 1.334.05c.364.066.734.195.96.465.12.144.193.32.2.518.007.192-.047.382-.138.563a1.04 1.04 0 0 1-.354.416.856.856 0 0 1-.51.138c-.331-.014-.654-.196-.933-.417a5.712 5.712 0 0 1-.911-.95 11.651 11.651 0 0 0-1.997.406 11.307 11.307 0 0 1-1.02 1.51c-.292.35-.609.656-.927.787a.793.793 0 0 1-.58.029zm1.379-1.901c-.166.076-.32.156-.459.238-.328.194-.541.383-.647.547-.094.145-.096.25-.04.361.01.022.02.036.026.044a.266.266 0 0 0 .035-.012c.137-.056.355-.235.635-.572a8.18 8.18 0 0 0 .45-.606zm1.64-1.33a12.71 12.71 0 0 1 1.01-.193 11.744 11.744 0 0 1-.51-.858 20.801 20.801 0 0 1-.5 1.05zm2.446.45c.15.163.296.3.435.41.24.19.407.253.498.256a.107.107 0 0 0 .07-.015.307.307 0 0 0 .094-.125.436.436 0 0 0 .059-.2.095.095 0 0 0-.026-.063c-.052-.062-.2-.152-.518-.209a3.876 3.876 0 0 0-.612-.053zM8.078 7.8a6.7 6.7 0 0 0 .2-.828c.031-.188.043-.343.038-.465a.613.613 0 0 0-.032-.198.517.517 0 0 0-.145.04c-.087.035-.158.106-.196.283-.04.192-.03.469.046.822.024.111.054.227.09.346z"/>
                    </svg>
                    %s
                </a>',
                $url,
                ($pageName === Crud::PAGE_INDEX) ? '0' : '5px',
                $text
            );
        }

        if ($pageName === Crud::PAGE_DETAIL) {
            return sprintf(
                '%s
                <a href="#" onclick="showImageModal(\'%s\'); return false;" title="Ver imagen completa">
                    <img src="%s" alt="Archivo" style="max-width: 300px; max-height: 300px; border: 1px solid #ddd; border-radius: 4px; padding: 5px; cursor: pointer;">
                </a>
                
                <div id="%s" class="image-modal">
                    <div class="modal-content">
                        <img src="%s" alt="Archivo">
                    </div>
                    <button class="modal-close-btn" onclick="closeImageModal(\'%s\')">&times;</button>
                </div>',
                $assets, md5($url . $suffix), $url, md5($url . $suffix), $url, md5($url . $suffix)
            );
        }

        return sprintf(
            '%s
            <a href="#" onclick="showImageModal(\'%s\'); return false;" style="display: inline-flex; align-items: center; text-decoration: none; color: #007bff;" title="Ver archivo">
                <svg width="20" height="20" fill="currentColor" style="margin-right: 5px;" viewBox="0 0 16 16">
                    <path d="M6.002 5.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0z"/>
                    <path d="M2.002 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2h-12zm12 1a1 1 0 0 1 1 1v6.5l-3.777-1.947a.5.5 0 0 0-.577.09l-3.71 3.71-2.66-1.772a.5.5 0 0 0-.63.062L1.002 12V3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2a1 1 0 0 1 1-1h5.5v2z"/>
                </svg>
            </a>
            
            <div id="%s" class="image-modal">
                <div class="modal-content">
                    <img src="%s" alt="Archivo">
                </div>
                <button class="modal-close-btn" onclick="closeImageModal(\'%s\')">&times;</button>
            </div>', 
            $assets, 
            md5($url . $suffix), 
            md5($url . $suffix), 
            $url, 
            md5($url . $suffix)
        );
    }

    /**
     * Campo de imagen estándar con modal para índice y detalle.
     * Simplifica la creación de campos de imagen en los controllers.
     */
    protected function createImageField(string $property, string $label, string $uploadPath, ?string $pageName = null): TextField
    {
        $field = TextField::new($property, $label);
        
        $field->formatValue(function ($value, $entity) use ($uploadPath, $property, $pageName) {
            $getter = 'get' . str_replace(' ', '', ucwords(str_replace('_', ' ', $property)));
            $fileValue = (is_string($value) && $value !== '') ? $value : (method_exists($entity, $getter) ? $entity->$getter() : $value);
            
            if (!is_string($fileValue) || $fileValue === '' || $fileValue === null) {
                return '';
            }

            $storageName = $this->getStorageName($property);
            $storagePath = $this->getStoragePath($property);
            
            if ($storageName !== 'docfile.storage') {
                if ($this->container->has($storageName)) {
                    $storage = $this->container->get($storageName);
                    try {
                        $fullPath = $storagePath . $fileValue;
                        $fileExists = $storage->has($fullPath);
                        
                        if (!$fileExists) {
                            return '';
                        }
                    } catch (\Exception $e) {
                        return '';
                    }
                }
            }

            $storageName = $this->getStorageName($property);
            if ($storageName === 'docfile.storage') {
                $uploadPath = '/admin/docfile2/view/';
            }
            
            return $this->formatImageValue($fileValue, $pageName ?? Crud::PAGE_INDEX, $property, $uploadPath);
        });
        
        $field->setLabel($label);
        
        return $field;
    }

    /**
     * Retorna la URL base para las subidas de archivos.
     * Busca la constante UPLOAD_URL en el controlador hijo.
     */
    protected function getUploadUrl(): string
    {
        try {
            $reflection = new \ReflectionClass(static::class);
            
            if ($reflection->hasConstant('UPLOAD_URL')) {
                return $reflection->getConstant('UPLOAD_URL');
            }

            $storageName = $this->getStorageName('');
            $storagePath = $this->getStoragePath('');

            $baseUrl = match ($storageName) {
                'docfile.storage' => '/admin/docfile2/view/',
                default => '/uploads/',
            };

            return ($storageName === 'docfile.storage') 
                ? $baseUrl 
                : $baseUrl . $storagePath;
        } catch (\Exception $e) {}
        
        return '/uploads/';
    }
    protected function getStorageName(string $property): string
    {
        try {
            $reflection = new \ReflectionClass(static::class);
            if ($reflection->hasConstant('STORAGE')) {
                $storage = $reflection->getConstant('STORAGE');
                if (is_array($storage) && isset($storage[0])) return $storage[0];
            }

            if ($reflection->hasConstant('STORAGE_NAME')) {
                return $reflection->getConstant('STORAGE_NAME');
            }

            $mappingName = $this->getVichMappingName($property);
            if ($mappingName) {
                $vichConfig = $this->container->get('parameter_bag')->get('vich_uploader.mappings');
                if (isset($vichConfig[$mappingName]['upload_destination'])) {
                    return $vichConfig[$mappingName]['upload_destination'];
                }
            }
        } catch (\Exception $e) {}

        return 'local.storage';
    }

    protected function getStoragePath(string $property): string
    {
        try {
            $reflection = new \ReflectionClass(static::class);
            if ($reflection->hasConstant('STORAGE')) {
                $storage = $reflection->getConstant('STORAGE');
                if (is_array($storage) && isset($storage[1])) return $storage[1];
            }

            if ($reflection->hasConstant('STORAGE_PATH')) {
                return $reflection->getConstant('STORAGE_PATH');
            }

            $mappingName = $this->getVichMappingName($property);
            if ($mappingName) {
                $vichConfig = $this->container->get('parameter_bag')->get('vich_uploader.mappings');
                if (isset($vichConfig[$mappingName]['directory_namer']['options']['subdir'])) {
                    return $vichConfig[$mappingName]['directory_namer']['options']['subdir'] . '/';
                }
            }

            if ($this->getStorageName($property) === 'local.storage' && $reflection->hasConstant('UPLOAD_URL')) {
                $url = $reflection->getConstant('UPLOAD_URL');
                return ltrim(str_replace('/uploads/', '', $url), '/');
            }
        } catch (\Exception $e) {}

        return '';
    }

    protected function getVichMappingName(string $property): ?string
    {
        try {
            $entityFqcn = static::getEntityFqcn();
            
            $reflection = new \ReflectionClass($entityFqcn);
            $properties = $reflection->getProperties();
            
            foreach ($properties as $reflectionProperty) {
                foreach ($reflectionProperty->getAttributes() as $attribute) {
                    if (str_contains($attribute->getName(), 'UploadableField')) {
                        $args = $attribute->getArguments();
                        $fileNameProperty = $args['fileNameProperty'] ?? $args[1] ?? $args[0] ?? null;
                        
                        if (empty($property) || $fileNameProperty === $property) {
                            return $args['mapping'] ?? $args[0] ?? null;
                        }
                    }
                }
            }
        } catch (\Exception $e) {}
        
        return null;
    }

    public static function getSubscribedServices(): array
    {
        return array_merge(parent::getSubscribedServices(), [
            'local.storage' => '?League\Flysystem\FilesystemOperator',
            'docfile.storage' => '?League\Flysystem\FilesystemOperator',
        ]);
    }
}
