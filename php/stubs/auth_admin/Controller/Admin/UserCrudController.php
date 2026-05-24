<?php

namespace App\Controller\Admin;

use App\Controller\Admin\Base\BaseCrudController;
use App\Entity\User;
use EasyCorp\Bundle\EasyAdminBundle\Config\Action;
use EasyCorp\Bundle\EasyAdminBundle\Config\Actions;
use EasyCorp\Bundle\EasyAdminBundle\Config\Crud;
use EasyCorp\Bundle\EasyAdminBundle\Config\Filters;
use EasyCorp\Bundle\EasyAdminBundle\Context\AdminContext;
use EasyCorp\Bundle\EasyAdminBundle\Field\BooleanField;
use EasyCorp\Bundle\EasyAdminBundle\Field\ChoiceField;
use EasyCorp\Bundle\EasyAdminBundle\Field\DateTimeField;
use EasyCorp\Bundle\EasyAdminBundle\Field\IdField;
use EasyCorp\Bundle\EasyAdminBundle\Field\TextField;
use EasyCorp\Bundle\EasyAdminBundle\Router\AdminUrlGenerator;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Form\Extension\Core\Type\PasswordType;
use Symfony\Component\Form\Extension\Core\Type\RepeatedType;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

class UserCrudController extends BaseCrudController
{
    public const ENTITY = ['Usuario', 'Usuarios'];

    public const AUDIT_FIELDS_EXTRA = ['password'];

    public const INDEX_INCLUDES = ['login', 'roles', 'activo', 'creadoEl'];

    public function __construct(
        private readonly UserPasswordHasherInterface $passwordHasher,
        private readonly AdminUrlGenerator $adminUrlGenerator,
    ) {}

    public static function getEntityFqcn(): string
    {
        return User::class;
    }

    // -------------------------------------------------------------------------
    // CRUD config
    // -------------------------------------------------------------------------

    public function configureCrud(Crud $crud): Crud
    {
        return parent::configureCrud($crud)
            ->setDefaultSort(['id' => 'DESC'])
            ->setSearchFields(['login'])
        ;
    }

    public function configureActions(Actions $actions): Actions
    {
        $resetPassword = Action::new('resetPassword', 'Resetear contraseña', 'fa fa-key')
            ->linkToCrudAction('resetPassword')
            ->addCssClass('btn btn-warning btn-sm')
            ->displayIf(fn ($entity) => $entity instanceof User);

        return parent::configureActions($actions)
            ->add(Crud::PAGE_INDEX, $resetPassword)
            ->add(Crud::PAGE_DETAIL, $resetPassword)
        ;
    }

    public function configureFilters(Filters $filters): Filters
    {
        return $this->applyFilters($filters, ['activo']);
    }

    // -------------------------------------------------------------------------
    // Fields
    // -------------------------------------------------------------------------

    public function configureFields(string $pageName): iterable
    {
        yield IdField::new('id', 'ID')->onlyOnIndex();

        yield TextField::new('login', 'Usuario')
            ->setColumns(6)
            ->setRequired(true);

        // Campo de password solo en formularios (new/edit)
        if ($pageName === Crud::PAGE_NEW) {
            yield $this->passwordField(required: true);
        }

        if ($pageName === Crud::PAGE_EDIT) {
            yield $this->passwordField(required: false)
                ->setHelp('Dejá vacío para mantener la contraseña actual.');
        }

        yield ChoiceField::new('roles', 'Roles')
            ->setChoices([
                'Usuario'        => 'ROLE_USER',
                'Administrador'  => 'ROLE_ADMIN',
            ])
            ->allowMultipleChoices()
            ->renderExpanded(false)
            ->setColumns(6);

        yield BooleanField::new('activo', 'Activo')
            ->renderAsSwitch(true)
            ->setColumns(3);

        yield DateTimeField::new('creadoEl', 'Creado')
            ->setFormat('dd/MM/yyyy HH:mm')
            ->hideOnForm()
            ->setColumns(3);

        yield DateTimeField::new('modificadoEl', 'Modificado')
            ->setFormat('dd/MM/yyyy HH:mm')
            ->hideOnForm()
            ->onlyOnDetail();
    }

    // -------------------------------------------------------------------------
    // Persist / Update — hasheo de password
    // -------------------------------------------------------------------------

    public function persistEntity(EntityManagerInterface $em, $entity): void
    {
        $this->hashPasswordIfSet($entity);
        parent::persistEntity($em, $entity);
    }

    public function updateEntity(EntityManagerInterface $em, $entity): void
    {
        $this->hashPasswordIfSet($entity);
        parent::updateEntity($em, $entity);
    }

    // -------------------------------------------------------------------------
    // Acción custom: resetear password
    // -------------------------------------------------------------------------

    public function resetPassword(AdminContext $context): Response
    {
        /** @var User $user */
        $user = $context->getEntity()->getInstance();

        // Generar contraseña temporal
        $tempPassword = substr(str_shuffle('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'), 0, 10);
        $hashed = $this->passwordHasher->hashPassword($user, $tempPassword);
        $user->setPassword($hashed);

        $this->container->get('doctrine')->getManagerForClass(User::class)->flush();

        $this->addFlash('success', "✅ Contraseña reseteada. Nueva contraseña temporal: <strong>{$tempPassword}</strong>");

        $url = $this->adminUrlGenerator
            ->setController(self::class)
            ->setAction(Action::INDEX)
            ->generateUrl();

        return $this->redirect($url);
    }

    // -------------------------------------------------------------------------
    // Helpers privados
    // -------------------------------------------------------------------------

    private function passwordField(bool $required): TextField
    {
        return TextField::new('password', 'Contraseña')
            ->setFormType(RepeatedType::class)
            ->setFormTypeOptions([
                'type'            => PasswordType::class,
                'first_options'   => ['label' => 'Contraseña', 'attr' => ['autocomplete' => 'new-password']],
                'second_options'  => ['label' => 'Repetir contraseña', 'attr' => ['autocomplete' => 'new-password']],
                'mapped'          => false,
                'required'        => $required,
            ])
            ->setColumns(6)
            ->onlyOnForms();
    }

    private function hashPasswordIfSet(User $user): void
    {
        // El campo password viene del formulario como campo no mapeado
        $request = $this->container->get('request_stack')->getCurrentRequest();
        $formData = $request?->request->all();

        // EasyAdmin anida los datos bajo el nombre del formulario
        $password = null;
        foreach ($formData as $key => $value) {
            if (is_array($value) && isset($value['password']['first'])) {
                $password = $value['password']['first'];
                break;
            }
        }

        if (!empty($password)) {
            $user->setPassword(
                $this->passwordHasher->hashPassword($user, $password)
            );
        }
    }
}
