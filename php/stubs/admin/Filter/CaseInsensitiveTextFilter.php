<?php

namespace App\Filter;

use Doctrine\ORM\QueryBuilder;
use EasyCorp\Bundle\EasyAdminBundle\Contracts\Filter\FilterInterface;
use EasyCorp\Bundle\EasyAdminBundle\Dto\EntityDto;
use EasyCorp\Bundle\EasyAdminBundle\Dto\FieldDto;
use EasyCorp\Bundle\EasyAdminBundle\Dto\FilterDataDto;
use EasyCorp\Bundle\EasyAdminBundle\Filter\FilterTrait;
use EasyCorp\Bundle\EasyAdminBundle\Form\Filter\Type\TextFilterType;

class CaseInsensitiveTextFilter implements FilterInterface
{
    use FilterTrait;

    public static function new(string $propertyName, ?string $label = null): self
    {
        return (new self())
            ->setFilterFqcn(__CLASS__)
            ->setProperty($propertyName)
            ->setLabel($label)
            ->setFormType(TextFilterType::class)
            ->setFormTypeOption('translation_domain', 'EasyAdminBundle');
    }

    public function apply(QueryBuilder $queryBuilder, FilterDataDto $filterDataDto, ?FieldDto $fieldDto, EntityDto $entityDto): void
    {
        if (empty($filterDataDto->getValue())) {
            return;
        }

        $alias = $filterDataDto->getEntityAlias();
        $property = $filterDataDto->getProperty();
        $comparison = $filterDataDto->getComparison();
        $parameterName = $filterDataDto->getParameterName();
        $value = $filterDataDto->getValue();

        // Apply LOWER() to both the field and the value for case-insensitive comparison
        // We handle the most common text comparisons
        
        switch ($comparison) {
            case 'contains':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) LIKE LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, '%' . $value . '%');
                break;
                
            case 'not_contains':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) NOT LIKE LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, '%' . $value . '%');
                break;
                
            case 'starts_with':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) LIKE LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, $value . '%');
                break;
                
            case 'ends_with':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) LIKE LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, '%' . $value);
                break;
                
            case '=':
            case '==':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) = LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, $value);
                break;
                
            case '!=':
            case '<>':
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) != LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, $value);
                break;
                
            default:
                // Fallback to contains if unknown
                $queryBuilder->andWhere(sprintf('LOWER(%s.%s) LIKE LOWER(:%s)', $alias, $property, $parameterName))
                    ->setParameter($parameterName, '%' . $value . '%');
                break;
        }
    }
}
