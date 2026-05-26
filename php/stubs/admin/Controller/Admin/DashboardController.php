<?php

namespace App\Controller\Admin;

use EasyCorp\Bundle\EasyAdminBundle\Attribute\AdminDashboard;
use EasyCorp\Bundle\EasyAdminBundle\Config\Dashboard;
use EasyCorp\Bundle\EasyAdminBundle\Config\MenuItem;
use EasyCorp\Bundle\EasyAdminBundle\Controller\AbstractDashboardController;
use Symfony\Component\HttpFoundation\Response;

#[AdminDashboard(routePath: '/admin', routeName: 'admin')]
class DashboardController extends AbstractDashboardController
{
    public function index(): Response
    {
        return $this->render('admin/dashboard.html.twig');
    }

    public function configureDashboard(): Dashboard
    {
        return Dashboard::new()
            ->setTitle('Panel de Administración')
            ->setFaviconPath('favicon.ico')
            ->renderContentMaximized()
        ;
    }

    public function configureMenuItems(): iterable
    {
        yield MenuItem::linkToDashboard('Inicio', 'fa fa-home');

        // ── Agregar aquí los items de menú de tus entidades ──────────────────
        // Ejemplo:
        // yield MenuItem::section('Gestión');
        // yield MenuItem::linkToCrud('Productos', 'fa fa-box', Producto::class);

        // ── Usuarios (se incluye automáticamente si USE_AUTH=true) ───────────
        // @@USER_MENU_ITEM@@
    }
}

